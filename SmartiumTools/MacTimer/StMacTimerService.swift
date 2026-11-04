//
//  StMacTimerService.swift
//  SmartiumTools
//
//  The Mac's timer, without AlarmKit (handoff v0.7). Counts down in the app,
//  schedules a local notification for the end (UserNotifications), plays the
//  chosen end sound (§3) and mirrors its state to `StLiveSurfaces.timer`.
//  One timer per device: nothing syncs but recents, message and sound (§5).
//

import SwiftUI

#if SMARTIUM_APP && os(macOS)
import AppKit
import UserNotifications

@Observable
final class StMacTimerService: NSObject {
    static let shared = StMacTimerService()

    private static let notificationID = "dev.smartium.tools.macTimer.end"

    private(set) var phase: StTimerSnapshot.Phase = .idle
    /// End of the countdown while running.
    private(set) var fireDate: Date?
    /// Remaining seconds while paused.
    private(set) var pausedRemaining: TimeInterval?
    /// Ring total, including live adjustments.
    private(set) var total: TimeInterval = 0
    /// Ticks while running, so the clock and the menu bar update.
    private(set) var now = Date.now
    /// Notifications were refused: the end alert only works with the app open.
    private(set) var notificationsDenied = false

    /// Recents, end message and sound, shared with the iPhone through iCloud.
    var limitimer = LimitimerSettings() {
        didSet {
            guard limitimer != oldValue, !isApplyingLoad else { return }
            let settings = limitimer
            Task.detached(priority: .utility) {
                await ICloudSettings.saveLimitimer(settings)
            }
        }
    }

    /// Duration the timer started with, for the notification body.
    @ObservationIgnored private var originalDuration: TimeInterval = 0
    @ObservationIgnored private var message = ""
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private var isApplyingLoad = false

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        restore()
    }

    // MARK: State

    var remaining: TimeInterval? {
        switch phase {
        case .running: max(0, (fireDate ?? now).timeIntervalSince(now))
        case .paused: pausedRemaining
        case .alerting: 0
        case .idle: nil
        }
    }

    /// Counting or paused: the menu bar item shows only then.
    var isActive: Bool {
        phase == .running || phase == .paused
    }

    /// Loads the shared settings and the notification permission, without asking.
    func load() async {
        let settings = await ICloudSettings.loadLimitimer()
        isApplyingLoad = true
        limitimer = settings
        isApplyingLoad = false
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        notificationsDenied = status == .denied
    }

    // MARK: Actions

    /// Starts a new timer, replacing the current one.
    func start(duration: TimeInterval, message: String) {
        // Recents saved before v0.4 may be longer than the limit.
        let duration = min(duration, StTimer.maxDuration)
        guard duration > 0 else { return }
        limitimer = limitimer.withRecent(duration: duration, message: message)
        self.message = message
        originalDuration = duration
        total = duration
        now = .now
        fireDate = now.addingTimeInterval(duration)
        pausedRemaining = nil
        phase = .running

        var snapshot = StLiveSurfaces.timer
        snapshot.lastDuration = duration
        snapshot.message = message
        StLiveSurfaces.timer = snapshot
        publish()
        startTicking()
        scheduleNotification()
    }

    /// Pauses, resumes, or stops a finished timer.
    func toggle() {
        switch phase {
        case .running:
            pausedRemaining = remaining
            fireDate = nil
            phase = .paused
            stopTicking()
            removeNotification()
        case .paused:
            now = .now
            fireDate = now.addingTimeInterval(pausedRemaining ?? 0)
            pausedRemaining = nil
            phase = .running
            startTicking()
            scheduleNotification()
        case .alerting:
            phase = .idle
        case .idle:
            return
        }
        publish()
    }

    /// Changes the remaining time without stopping, up to 2:00:00. Reaching 0
    /// cancels the timer; going past the total grows the ring with it.
    func adjust(by delta: TimeInterval) {
        guard isActive, let remaining else { return }
        let newRemaining = min((remaining + delta).rounded(.up), StTimer.maxDuration)
        guard newRemaining > 0 else {
            cancel()
            return
        }
        total = max(total, newRemaining)
        if phase == .running {
            now = .now
            fireDate = now.addingTimeInterval(newRemaining)
            scheduleNotification()
        } else {
            pausedRemaining = newRemaining
        }
        publish()
    }

    func cancel() {
        phase = .idle
        fireDate = nil
        pausedRemaining = nil
        stopTicking()
        removeNotification()
        publish()
    }

    /// Plays a sound once, as the preview when the user picks it.
    func preview(_ ringer: StTimerRinger) {
        ringer.soundName.flatMap { NSSound(named: NSSound.Name($0)) }?.play()
    }

    // MARK: Countdown

    private func startTicking() {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.now = .now
                if self.phase == .running, let fireDate = self.fireDate, self.now >= fireDate {
                    self.finish()
                    return
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    private func stopTicking() {
        tickTask?.cancel()
        tickTask = nil
    }

    /// The end with the app open: the screen shows "Encerrado!" and the
    /// chosen sound plays. The notification covers the app being closed.
    private func finish() {
        phase = .alerting
        fireDate = nil
        tickTask = nil
        publish()
        playEndSound()
    }

    private func playEndSound() {
        switch limitimer.ringer {
        case .silent:
            break
        case .system:
            // The notification plays the system sound; without permission
            // there is no notification, so the app plays one itself.
            if notificationsDenied {
                NSSound(named: NSSound.Name("Glass"))?.play()
            }
        default:
            preview(limitimer.ringer)
        }
    }

    // MARK: Notification

    /// Schedules the end notification for the current `fireDate`, replacing
    /// any earlier one. Asks for permission on first use.
    private func scheduleNotification() {
        removeNotification()
        guard let scheduledFireDate = fireDate else { return }
        let title = message.isEmpty ? LimitimerSettings.defaultEndMessage : message
        let body = "Timer de \(TimerFormat.duration(originalDuration))"
        let isSilent = limitimer.ringer == .silent

        Task {
            guard await authorizeNotifications() else { return }
            // The timer may have been paused or changed while asking.
            guard phase == .running, fireDate == scheduledFireDate else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = isSilent ? nil : .default
            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: max(1, scheduledFireDate.timeIntervalSinceNow),
                repeats: false
            )
            let request = UNNotificationRequest(identifier: Self.notificationID, content: content, trigger: trigger)
            try? await UNUserNotificationCenter.current().add(request)
        }
    }

    private func removeNotification() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
        center.removeDeliveredNotifications(withIdentifiers: [Self.notificationID])
    }

    private func authorizeNotifications() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted: Bool
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional:
            granted = true
        case .notDetermined:
            granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        default:
            granted = false
        }
        notificationsDenied = !granted
        return granted
    }

    // MARK: Snapshot

    /// Picks up a timer that was running when the app quit; the system keeps
    /// its notification. A timer that ended meanwhile goes back to idle.
    private func restore() {
        let snapshot = StLiveSurfaces.timer
        message = snapshot.message
        total = snapshot.total ?? 0
        originalDuration = snapshot.total ?? snapshot.lastDuration
        switch snapshot.phase {
        case .running:
            if let fireDate = snapshot.fireDate, fireDate > .now {
                self.fireDate = fireDate
                phase = .running
                startTicking()
                return
            }
        case .paused:
            if let pausedRemaining = snapshot.pausedRemaining {
                self.pausedRemaining = pausedRemaining
                phase = .paused
                return
            }
        case .idle, .alerting:
            break
        }
        if snapshot.phase != .idle {
            publish()
        }
    }

    /// Writes the state for the Timer widgets (§4).
    private func publish() {
        var snapshot = StLiveSurfaces.timer
        snapshot.phase = phase
        snapshot.fireDate = fireDate
        snapshot.pausedRemaining = pausedRemaining
        snapshot.total = total > 0 ? total : nil
        StLiveSurfaces.timer = snapshot
        StLiveSurfaces.reloadTimer()
    }
}

extension StMacTimerService: UNUserNotificationCenterDelegate {
    /// With the app open the banner still shows; the system sound plays only
    /// for "Padrão do sistema", since the app plays its own sounds.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let ringer = await MainActor.run { limitimer.ringer }
        return ringer == .system ? [.banner, .list, .sound] : [.banner, .list]
    }

    /// v0.8: clicking the notification opens the window on the Timer tab.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await MainActor.run {
            _ = NSWorkspace.shared.open(StToolDestination.timer.url)
        }
    }
}
#endif
