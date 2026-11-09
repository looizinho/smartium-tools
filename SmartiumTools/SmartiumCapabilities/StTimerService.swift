//
//  StTimerService.swift
//  SmartiumTools
//
//  Schedules the Limitimer timer with AlarmKit and keeps `StLiveSurfaces.timer`
//  current for the Timer widgets and control (handoff v0.5). Used by the Timer
//  screen and by the timer intents, which run in the app process.
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
        save(snapshot)
    }

    /// The system alert's stop button already stopped the alarm.
    static func markStopped() {
        var snapshot = StLiveSurfaces.timer
        guard snapshot.phase != .idle else { return }
        snapshot.phase = .idle
        save(snapshot)
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

    /// "Reiniciar": counts the full total again from the start.
    static func restart() async throws {
        let snapshot = StLiveSurfaces.timer
        if let alarm = activeAlarm {
            try AlarmManager.shared.cancel(id: alarm.id)
        }
        try await start(snapshot.total ?? snapshot.lastDuration, message: snapshot.message)
    }

    private static func start(_ duration: TimeInterval, message: String) async throws {
        let duration = min(max(duration, 1), StTimer.maxDuration)
        try await schedule(duration: duration, message: message)
        var snapshot = StLiveSurfaces.timer
        snapshot.phase = .running
        snapshot.fireDate = Date.now.addingTimeInterval(duration)
        snapshot.total = duration
        save(snapshot)
    }

    // MARK: Snapshot

    /// A new timer from the Timer screen: widgets restart with this duration.
    static func recordStart(duration: TimeInterval, message: String) {
        var snapshot = StLiveSurfaces.timer
        snapshot.lastDuration = duration
        snapshot.message = message
        save(snapshot)
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
    }

    private static func save(_ snapshot: StTimerSnapshot) {
        StLiveSurfaces.timer = snapshot
        StLiveSurfaces.reloadTimer()
        StWatchSync.shared.timerChanged(snapshot)
    }

    private static func localizedTitle(_ text: String) -> LocalizedStringResource {
        LocalizedStringResource(String.LocalizationValue(text))
    }
}
#endif
