//
//  StTimerService.swift
//  SmartiumTools
//
//  Schedules the Limitimer timer with AlarmKit and keeps `StLiveSurfaces.timer`
//  current for the Timer widgets and control (handoff v0.5). Used by the Timer
//  screen and by the timer intents, which run in the app process.
//  v0.12: user actions go to the other devices (`commit`, `StTimerSync`),
//  and a timer another device wrote is adopted here (`adopt`).
//

import SwiftUI

#if SMARTIUM_APP && canImport(AlarmKit) && os(iOS)
import ActivityKit
import AlarmKit

@MainActor
enum StTimerService {
    enum ServiceError: LocalizedError {
        case unauthorized

        var errorDescription: String? {
            "O AlarmKit precisa estar autorizado para agendar timers."
        }
    }

    /// Ring total of a timer adopted from another device: AlarmKit only
    /// knows the remaining time it was scheduled with (v0.12).
    static var adoptedRingTotal: TimeInterval?

    /// The timer the app shows: counting, paused or ringing.
    static var activeAlarm: Alarm? {
        (try? AlarmManager.shared.alarms)?.first {
            $0.state == .countdown || $0.state == .paused || $0.state == .alerting
        }
    }

    static func schedule(
        duration: TimeInterval,
        message: String,
        tint: Color = StTool.timer.tone,
        startPaused: Bool = false
    ) async throws {
        guard try await AlarmManager.shared.requestAuthorization() == .authorized else {
            throw ServiceError.unauthorized
        }

        let alertTitle = message.isEmpty ? LimitimerSettings.defaultEndMessage : message
        let presentation = AlarmPresentation(
            alert: .init(title: localizedTitle(alertTitle)),
            countdown: .init(
                title: localizedTitle("Timer"),
                pauseButton: AlarmButton(text: "Pausar", textColor: tint, systemImageName: "pause.fill")
            ),
            paused: .init(
                title: "Pausado",
                resumeButton: AlarmButton(text: "Retomar", textColor: tint, systemImageName: "play.fill")
            )
        )
        let attributes = AlarmAttributes<SmartiumAlarmMetadata>(
            presentation: presentation,
            metadata: SmartiumAlarmMetadata(tool: .timer),
            tintColor: tint
        )
        let id = UUID()
        adoptedRingTotal = nil
        _ = try await AlarmManager.shared.schedule(
            id: id,
            configuration: .timer(duration: duration, attributes: attributes, stopIntent: StopTimerIntent())
        )
        if startPaused {
            try AlarmManager.shared.pause(id: id)
        }
    }

    // MARK: Intents

    /// Toggle and widget button: `true` resumes, or starts the last duration
    /// when idle; `false` pauses. A ringing timer stops either way.
    static func setRunning(_ running: Bool) async throws {
        var snapshot = StLiveSurfaces.timer
        let now = Date.now

        guard let alarm = activeAlarm else {
            guard running else { return }
            try await start(snapshot.lastDuration, message: snapshot.message)
            return
        }

        switch alarm.state {
        case .alerting:
            try AlarmManager.shared.stop(id: alarm.id)
            snapshot.phase = .idle
        case .paused where running:
            let remaining = liveRemaining(at: now) ?? snapshot.pausedRemaining ?? snapshot.lastDuration
            try AlarmManager.shared.resume(id: alarm.id)
            snapshot.phase = .running
            snapshot.fireDate = now.addingTimeInterval(remaining)
        case .countdown where !running:
            let remaining = liveRemaining(at: now) ?? snapshot.remaining(at: now)
            try AlarmManager.shared.pause(id: alarm.id)
            snapshot.pausedRemaining = remaining
            snapshot.phase = .paused
        default:
            return
        }
        snapshot.total = snapshot.total ?? liveTotal()
        commit(snapshot)
    }

    /// The system alert's stop button already stopped the alarm.
    static func markStopped() {
        var snapshot = StLiveSurfaces.timer
        guard snapshot.phase != .idle else { return }
        snapshot.phase = .idle
        commit(snapshot)
    }

    /// Remaining time from AlarmKit's Live Activity, which is current even
    /// when the snapshot isn't (e.g. a timer started before the app wrote one).
    private static func liveRemaining(at date: Date) -> TimeInterval? {
        for activity in Activity<AlarmAttributes<SmartiumAlarmMetadata>>.activities {
            switch activity.content.state.mode {
            case .countdown(let countdown):
                return max(0, countdown.fireDate.timeIntervalSince(date))
            case .paused(let paused):
                return max(0, paused.totalCountdownDuration - paused.previouslyElapsedDuration)
            default:
                continue
            }
        }
        return nil
    }

    private static func liveTotal() -> TimeInterval? {
        for activity in Activity<AlarmAttributes<SmartiumAlarmMetadata>>.activities {
            switch activity.content.state.mode {
            case .countdown(let countdown): return countdown.totalCountdownDuration
            case .paused(let paused): return paused.totalCountdownDuration
            default: continue
            }
        }
        return nil
    }

    /// "Zerar" (v0.12.2 §1): back to the set duration and stopped, as the
    /// Timer screen's button does. `lastDuration` stays, so Iniciar starts
    /// it again from the top.
    static func reset() throws {
        if let alarm = activeAlarm {
            try AlarmManager.shared.cancel(id: alarm.id)
        }
        var snapshot = StLiveSurfaces.timer
        snapshot.phase = .idle
        snapshot.fireDate = nil
        snapshot.pausedRemaining = nil
        commit(snapshot)
    }

    private static func start(_ duration: TimeInterval, message: String) async throws {
        let duration = min(max(duration, 1), StTimer.maxDuration)
        try await schedule(duration: duration, message: message)
        var snapshot = StLiveSurfaces.timer
        snapshot.phase = .running
        snapshot.fireDate = Date.now.addingTimeInterval(duration)
        snapshot.pausedRemaining = nil
        snapshot.total = duration
        commit(snapshot)
    }

    // MARK: Snapshot

    /// The Timer screen scheduled a timer: a new one (`isNew`, which widgets
    /// restart with) or an adjustment, which keeps the ring's `total`.
    static func recordSchedule(
        duration: TimeInterval,
        message: String,
        total: TimeInterval,
        paused: Bool,
        isNew: Bool
    ) {
        var snapshot = StLiveSurfaces.timer
        if isNew {
            snapshot.lastDuration = duration
        }
        snapshot.message = message
        snapshot.phase = paused ? .paused : .running
        snapshot.fireDate = paused ? nil : Date.now.addingTimeInterval(duration)
        snapshot.pausedRemaining = paused ? duration : nil
        snapshot.total = total
        commit(snapshot)
    }

    /// A user action on the Timer screen that AlarmKit already applied.
    static func recordChange(_ change: (inout StTimerSnapshot) -> Void) {
        var snapshot = StLiveSurfaces.timer
        change(&snapshot)
        commit(snapshot)
    }

    /// Mirrors the Timer screen's state; writes only when something changed.
    static func publish(state: Alarm.State?, remaining: TimeInterval?, total: TimeInterval?) {
        var snapshot = StLiveSurfaces.timer
        let now = Date.now
        switch state {
        case .countdown:
            guard let remaining else { return }
            snapshot.phase = .running
            snapshot.fireDate = now.addingTimeInterval(remaining)
        case .paused:
            snapshot.phase = .paused
            snapshot.pausedRemaining = remaining
        case .alerting:
            snapshot.phase = .alerting
        default:
            snapshot.phase = .idle
        }
        snapshot.total = total ?? snapshot.total

        let current = StLiveSurfaces.timer
        let sameFireDate = abs((current.fireDate ?? .distantPast).timeIntervalSince(snapshot.fireDate ?? .distantPast)) < 1
        let samePaused = abs((current.pausedRemaining ?? -1) - (snapshot.pausedRemaining ?? -1)) < 1
        guard current.phase != snapshot.phase || current.total != snapshot.total
                || (snapshot.phase == .running && !sameFireDate)
                || (snapshot.phase == .paused && !samePaused) else { return }
        save(snapshot)

        // v0.12: changes this app didn't make itself also go to the other
        // devices: pause and resume from the system's countdown buttons, and
        // the end. Never right after an adoption, which is still settling.
        let fromSystem = (current.phase == .running && snapshot.phase == .paused)
            || (current.phase == .paused && snapshot.phase == .running)
            || (current.phase != .alerting && snapshot.phase == .alerting)
        if fromSystem, !StTimerSync.shared.isSettling {
            StTimerSync.shared.publish(snapshot)
        }
    }

    // MARK: Other devices (v0.12)

    /// A user action (or the end) here: saved, then sent to the other devices.
    static func commit(_ snapshot: StTimerSnapshot) {
        save(snapshot)
        StTimerSync.shared.publish(snapshot)
    }

    /// A newer timer from another device: AlarmKit is set to match it, then
    /// the snapshot is saved without writing back (§1.2–1.3).
    static func adopt(_ remote: StTimerSnapshot) async {
        let alarm = activeAlarm
        var snapshot = StLiveSurfaces.timer
        snapshot.message = remote.message
        snapshot.lastDuration = remote.lastDuration

        switch remote.phase {
        case .alerting:
            // The end: a timer still counting here rings on its own, and one
            // already ringing keeps ringing. Only a paused one is out of step.
            guard alarm?.state == .paused, let alarm else {
                StLiveSurfaces.publishTimer(snapshot)
                return
            }
            try? AlarmManager.shared.cancel(id: alarm.id)
            snapshot.phase = .idle
            snapshot.fireDate = nil
            snapshot.pausedRemaining = nil
        case .idle:
            if let alarm {
                try? AlarmManager.shared.cancel(id: alarm.id)
            }
            snapshot.phase = .idle
            snapshot.fireDate = nil
            snapshot.pausedRemaining = nil
        case .running, .paused:
            let remaining = remote.remaining(at: .now)
            guard remaining >= 1 else { return }
            let isSame = alarm != nil && StLiveSurfaces.timer.phase == remote.phase
                && abs((StLiveSurfaces.timer.fireDate ?? .distantPast).timeIntervalSince(remote.fireDate ?? .distantPast)) < 1
                && abs((StLiveSurfaces.timer.pausedRemaining ?? -1) - (remote.pausedRemaining ?? -1)) < 1
            if !isSame {
                if let alarm {
                    try? AlarmManager.shared.cancel(id: alarm.id)
                }
                do {
                    try await schedule(duration: remaining, message: remote.message, startPaused: remote.phase == .paused)
                } catch {
                    // No AlarmKit permission: the snapshot still follows, so
                    // widgets and the watch show the shared timer.
                }
            }
            snapshot.phase = remote.phase
            snapshot.fireDate = remote.phase == .running ? remote.fireDate : nil
            snapshot.pausedRemaining = remote.phase == .paused ? remaining : nil
            snapshot.total = remote.total
            adoptedRingTotal = remote.total
        }
        save(snapshot)
    }

    private static func save(_ snapshot: StTimerSnapshot) {
        StLiveSurfaces.publishTimer(snapshot)
        StWatchSync.shared.timerChanged(snapshot)
    }

    private static func localizedTitle(_ text: String) -> LocalizedStringResource {
        LocalizedStringResource(String.LocalizationValue(text))
    }
}
#endif
