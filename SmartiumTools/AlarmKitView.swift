//
//  AlarmKitView.swift
//  SmartiumTools
//
//  Created by Luiz Neto on 28/10/26.
//

import SwiftUI

#if canImport(AlarmKit) && os(iOS)
import ActivityKit
import AlarmKit
import Observation
#endif

struct AlarmKitView: View {
    var body: some View {
        #if canImport(AlarmKit) && os(iOS)
        AlarmKitViewContent()
        #else
        StAdaptiveToolLayout(tool: .timer, tag: "Timer") { size in
            StTimerRing(
                size: size,
                fraction: 1,
                label: "DEFINIDO",
                clock: "05:00",
                status: "Pronto"
            )
        } controls: {
            StToolHeader(
                title: "Timer",
                subtitle: "Disponível no iPhone (AlarmKit)",
                tool: .timer,
                status: .configured
            )
        }
        #endif
    }
}

/// Timer hero (v0.2): Menta progress ring, Sky tick ring, label + clock + status.
struct StTimerRing: View {
    let size: CGFloat
    /// Remaining fraction, 0–1.
    let fraction: Double
    let label: String
    let clock: String
    let status: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let timer = StTool.timer
        let sky = StAccent.sky
        // SVG viewBox 100: ring r44 stroke 5, ticks r37 stroke 1.6.
        let unit = size / 100
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        stops: [
                            .init(color: timer.opacity(0.22), location: 0),
                            .init(color: sky.color(opacity: 0.08), location: 0.5),
                            .init(color: timer.opacity(0), location: 0.7)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: size * 1.12 * 0.5
                    )
                )
                .padding(-size * 0.06)

            Circle()
                .stroke(timer.opacity(0.14), lineWidth: 5 * unit)
                .frame(width: 88 * unit, height: 88 * unit)

            Circle()
                .trim(from: 0, to: min(max(fraction, 0), 1))
                .stroke(timer.tone, style: StrokeStyle(lineWidth: 5 * unit, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 88 * unit, height: 88 * unit)
                .animation(reduceMotion ? nil : .linear(duration: 0.9), value: fraction)

            Circle()
                .stroke(
                    sky.color(opacity: 0.45),
                    style: StrokeStyle(lineWidth: 1.6 * unit, lineCap: .round, dash: [0.1 * unit, 3.77 * unit])
                )
                .frame(width: 74 * unit, height: 74 * unit)

            VStack(spacing: 2) {
                Text(label)
                    .font(.stTag)
                    .tracking(1.4)
                    .foregroundStyle(sky.color)
                Text(clock)
                    .font(.system(size: (size * 0.2).rounded(), weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .tracking(-1)
                    .foregroundStyle(Color.stTextPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                    .animation(reduceMotion ? nil : .snappy, value: clock)
                Text(status)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.stTextPrimary.opacity(0.55))
            }
            .frame(width: 70 * unit)
            .accessibilityElement(children: .combine)
        }
        .frame(width: size, height: size)
    }
}

#if canImport(AlarmKit) && os(iOS)
private nonisolated enum TimerFormat {
    static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let remainingSeconds = total % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        }

        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }

}

/// Timer shortcuts (v0.2 "ATALHOS").
private struct TimerShortcut: Hashable {
    let seconds: Int
    let title: String
    let color: StRGB
    var message: String? = nil

    static let all: [TimerShortcut] = [
        TimerShortcut(seconds: 60, title: "1 min", color: StAccent.sky),
        TimerShortcut(seconds: 300, title: "5 min", color: StTool.timer.rgb),
        TimerShortcut(seconds: 600, title: "10 min", color: StTool.fx.rgb),
        TimerShortcut(seconds: 1_500, title: "Pomodoro", color: StTool.voice.rgb, message: "Pomodoro"),
        TimerShortcut(seconds: 2_700, title: "45 min", color: StTool.orb.rgb)
    ]
}

private struct AlarmKitViewContent: View {
    @State private var manager = AlarmKitManager()
    @State private var selectedHours = 0
    @State private var selectedMinutes = 5
    @State private var selectedSeconds = 0
    @State private var limitimerSettings = LimitimerSettings()

    var body: some View {
        StAdaptiveToolLayout(tool: .timer, tag: "Timer") { size in
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = manager.remainingSeconds(at: context.date)
                let total = manager.totalDuration ?? selectedDuration
                StTimerRing(
                    size: size,
                    fraction: remaining.map { total > 0 ? $0 / total : 0 } ?? 1,
                    label: remaining == nil ? "DEFINIDO" : "RESTANTE",
                    clock: TimerFormat.duration(remaining ?? selectedDuration),
                    status: ringStatus
                )
            }
        } controls: {
            StToolHeader(
                title: "Timer",
                subtitle: headerStatus.title,
                tool: .timer,
                status: headerStatus.dot
            )
            durationPicker
            controls
            messageField
            StChipSection(
                title: "Atalhos",
                dot: StTool.timer.secondary,
                items: TimerShortcut.all,
                label: \.title,
                color: \.color,
                isOn: { Double($0.seconds) == currentDuration },
                select: startShortcut
            )
            if !limitimerSettings.recents.isEmpty {
                recents
            }
        }
        .alert("Timer", item: Binding(
            get: { manager.lastErrorMessage.map { IdentifiedAlarmError(message: $0) } },
            set: { newValue in
                if newValue == nil {
                    manager.clearError()
                }
            }
        )) { _ in
        } message: { error in
            Text(error.message)
        }
        .onChange(of: limitimerSettings.endMessage) { _, _ in
            saveTimerSettings()
        }
        .task {
            limitimerSettings = await ICloudSettings.loadLimitimer()
            await manager.observeAlarms()
        }
    }

    private var selectedDuration: TimeInterval {
        Double(selectedHours * 3_600 + selectedMinutes * 60 + selectedSeconds)
    }

    /// The running timer's total, or the picker value when idle.
    private var currentDuration: TimeInterval {
        activeAlarm == nil ? selectedDuration : (manager.totalDuration ?? selectedDuration)
    }

    /// The alarm the screen controls: the first one counting down, paused or alerting.
    private var activeAlarm: Alarm? {
        manager.alarms.first {
            $0.state == .countdown || $0.state == .paused || $0.state == .alerting
        }
    }

    private var headerStatus: (title: String, dot: StHeaderStatus) {
        switch activeAlarm?.state {
        case .countdown: ("Em andamento", .active)
        case .paused: ("Pausado", .ready)
        case .alerting: ("Encerrado!", .active)
        default: ("Pronto para iniciar", .configured)
        }
    }

    private var ringStatus: String {
        switch activeAlarm?.state {
        case .countdown: "Em andamento…"
        case .paused: "Pausado"
        case .alerting: "Encerrado!"
        default: "Pronto"
        }
    }

    // MARK: Picker

    private var durationPicker: some View {
        let timer = StTool.timer
        return HStack(spacing: 0) {
            picker(selection: $selectedHours, range: 0...23, label: "h")
            picker(selection: $selectedMinutes, range: 0...59, label: "min")
            picker(selection: $selectedSeconds, range: 0...59, label: "s")
        }
        .frame(width: 312, height: 150)
        .background {
            Capsule()
                .fill(timer.opacity(0.14))
                .overlay(Capsule().strokeBorder(timer.opacity(0.30), lineWidth: 1))
                .frame(height: 42)
                .allowsHitTesting(false)
        }
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.24),
                    .init(color: .black, location: 0.76),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .disabled(activeAlarm != nil)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.stInk800)
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(.white.opacity(0.06), lineWidth: 1)
                )
        )
    }

    private func picker(
        selection: Binding<Int>,
        range: ClosedRange<Int>,
        label: String
    ) -> some View {
        Picker(label, selection: selection) {
            ForEach(range, id: \.self) { value in
                Text("\(value)")
                    .monospacedDigit()
                    .tag(value)
            }
        }
        .pickerStyle(.wheel)
        .labelsHidden()
        .frame(width: 104, height: 150)
        .clipped()
        .overlay {
            Text(label)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(StTool.timer.tone)
                .offset(x: label == "min" ? 34 : 26)
                .allowsHitTesting(false)
        }
    }

    // MARK: Controls

    private var controls: some View {
        HStack(spacing: 10) {
            primaryButton
            StButton("Zerar", systemImage: "arrow.counterclockwise", kind: .iconTinted(.voice)) {
                if let activeAlarm {
                    manager.cancel(activeAlarm)
                }
            }
            .disabled(activeAlarm == nil)
        }
    }

    private var primaryButton: some View {
        let (title, symbol): (LocalizedStringKey, String) = switch activeAlarm?.state {
        case .countdown: ("Pausar", "pause.fill")
        case .paused: ("Retomar", "play.fill")
        case .alerting: ("Parar", "stop.fill")
        default: ("Iniciar", "play.fill")
        }

        return StButton(title, systemImage: symbol, kind: .primary(.timer)) {
            if let activeAlarm {
                manager.toggle(activeAlarm)
            } else {
                startTimer()
            }
        }
        .disabled(activeAlarm == nil && (selectedDuration == 0 || manager.isWorking))
    }

    private var messageField: some View {
        let sky = StAccent.sky
        let shape = RoundedRectangle(cornerRadius: StRadius.row, style: .continuous)
        return HStack(spacing: 12) {
            Image(systemName: "text.bubble")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(sky.color)
                .frame(width: 38, height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(sky.color(opacity: 0.16))
                )
                .accessibilityHidden(true)
            TextField("Mensagem de encerramento", text: $limitimerSettings.endMessage)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.stTextPrimary)
                .submitLabel(.done)
        }
        .padding(.leading, 10)
        .padding(.trailing, 16)
        .frame(height: 58)
        .background(shape.fill(Color.stInk800))
        .overlay(shape.strokeBorder(sky.color(opacity: 0.22), lineWidth: 1))
    }

    // MARK: Recents

    private var recents: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recentes")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .padding(.top, 8)
                .padding(.horizontal, 4)
                .accessibilityAddTraits(.isHeader)

            ForEach(Array(limitimerSettings.recents.enumerated()), id: \.element.id) { index, recent in
                recentRow(recent, color: [StAccent.sky, StTool.voice.rgb, StTool.fx.rgb, StTool.orb.rgb][index % 4])
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func recentRow(_ recent: LimitimerRecent, color: StRGB) -> some View {
        let shape = RoundedRectangle(cornerRadius: StRadius.row, style: .continuous)
        return HStack(alignment: .center, spacing: 14) {
            Image(systemName: "timer")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(color.color)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(color.color(opacity: 0.16))
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                Text(TimerFormat.duration(recent.duration))
                    .font(.system(size: 24, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.stTextPrimary)

                Text(recent.message.isEmpty ? "Sem mensagem" : recent.message)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.stTextPrimary.opacity(0.55))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button {
                applyDuration(Int(recent.duration))
                startTimer(duration: recent.duration, message: recent.message)
            } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(StTool.timer.tone)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(StTool.timer.opacity(0.16)))
            }
            .buttonStyle(StPressStyle())
            .accessibilityLabel("Iniciar \(TimerFormat.duration(recent.duration))")
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(Color.stInk800))
        .overlay(shape.strokeBorder(.white.opacity(0.05), lineWidth: 1))
    }

    private func startShortcut(_ shortcut: TimerShortcut) {
        applyDuration(shortcut.seconds)
        startTimer(duration: Double(shortcut.seconds), message: shortcut.message ?? limitimerSettings.endMessage)
    }

    private func applyDuration(_ seconds: Int) {
        selectedHours = seconds / 3_600
        selectedMinutes = (seconds % 3_600) / 60
        selectedSeconds = seconds % 60
    }

    private func startTimer(duration: TimeInterval? = nil, message: String? = nil) {
        let timerDuration = duration ?? selectedDuration
        guard timerDuration > 0 else { return }

        let endMessage = message ?? limitimerSettings.endMessage
        limitimerSettings = limitimerSettings.withRecent(
            duration: timerDuration,
            message: endMessage
        )
        saveTimerSettings()

        // The screen controls a single timer: a new start replaces the active one.
        if let activeAlarm {
            manager.cancel(activeAlarm)
        }

        Task {
            await manager.scheduleTimer(
                duration: timerDuration,
                tint: StTool.timer.tone,
                message: endMessage
            )
        }
    }

    private func saveTimerSettings() {
        let settings = limitimerSettings
        Task.detached(priority: .utility) {
            await ICloudSettings.saveLimitimer(settings)
        }
    }
}

private struct IdentifiedAlarmError: Identifiable {
    let id = UUID()
    let message: String
}

@Observable
private final class AlarmKitManager {
    private(set) var alarms: [Alarm] = []
    private(set) var presentationStates: [AlarmPresentationState] = []
    private(set) var authorizationState: AlarmManager.AuthorizationState = .notDetermined
    private(set) var isWorking = false
    /// Duration of the last timer this screen scheduled.
    private(set) var scheduledDuration: TimeInterval?
    private(set) var lastErrorMessage: String?

    private var presentationMonitorTask: Task<Void, Never>?
    private var contentMonitorTasks: [String: Task<Void, Never>] = [:]

    func clearError() {
        lastErrorMessage = nil
    }

    func observeAlarms() async {
        refresh()
        observePresentationStates()

        for await updatedAlarms in AlarmManager.shared.alarmUpdates {
            alarms = updatedAlarms
            refreshPresentationStates()
        }
    }

    func scheduleTimer(duration: TimeInterval, tint: Color, message: String) async {
        isWorking = true
        defer { isWorking = false }

        do {
            authorizationState = try await AlarmManager.shared.requestAuthorization()
            guard authorizationState == .authorized else {
                lastErrorMessage = "O AlarmKit precisa estar autorizado para agendar timers."
                return
            }

            let alertTitle = message.isEmpty ? LimitimerSettings.defaultEndMessage : message
            let presentation = AlarmPresentation(
                alert: .init(title: localizedTitle(alertTitle)),
                countdown: .init(
                    title: localizedTitle("Timer"),
                    pauseButton: AlarmButton(
                        text: "Pausar",
                        textColor: tint,
                        systemImageName: "pause.fill"
                    )
                ),
                paused: .init(
                    title: "Pausado",
                    resumeButton: AlarmButton(
                        text: "Retomar",
                        textColor: tint,
                        systemImageName: "play.fill"
                    )
                )
            )
            let attributes = AlarmAttributes<SmartiumAlarmMetadata>(
                presentation: presentation,
                metadata: SmartiumAlarmMetadata(tool: .timer),
                tintColor: tint
            )
            let configuration = AlarmManager.AlarmConfiguration.timer(
                duration: duration,
                attributes: attributes
            )

            _ = try await AlarmManager.shared.schedule(id: UUID(), configuration: configuration)
            scheduledDuration = duration
            refresh()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func toggle(_ alarm: Alarm) {
        do {
            switch alarm.state {
            case .paused:
                try AlarmManager.shared.resume(id: alarm.id)
            case .alerting:
                try AlarmManager.shared.stop(id: alarm.id)
            default:
                try AlarmManager.shared.pause(id: alarm.id)
            }

            refresh()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func cancel(_ alarm: Alarm) {
        do {
            try AlarmManager.shared.cancel(id: alarm.id)
            refresh()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func refresh() {
        authorizationState = AlarmManager.shared.authorizationState
        do {
            alarms = try AlarmManager.shared.alarms
        } catch {
            alarms = []
        }

        refreshPresentationStates()
    }

    private func refreshPresentationStates() {
        presentationStates = Activity<AlarmAttributes<SmartiumAlarmMetadata>>
            .activities
            .compactMap { $0.content.state }
    }

    private func observePresentationStates() {
        presentationMonitorTask?.cancel()
        contentMonitorTasks.values.forEach { $0.cancel() }
        contentMonitorTasks = [:]

        presentationMonitorTask = Task { [weak self] in
            for await activity in Activity<AlarmAttributes<SmartiumAlarmMetadata>>.activityUpdates {
                self?.observeContentUpdates(for: activity)
            }
        }
    }

    private func observeContentUpdates(for activity: Activity<AlarmAttributes<SmartiumAlarmMetadata>>) {
        contentMonitorTasks[activity.id]?.cancel()
        contentMonitorTasks[activity.id] = Task { [weak self] in
            for await _ in activity.contentUpdates {
                self?.refreshPresentationStates()
            }
        }
    }

    /// Total duration of the active countdown, from AlarmKit's presentation state.
    var totalDuration: TimeInterval? {
        for state in presentationStates {
            switch state.mode {
            case .countdown(let countdown): return countdown.totalCountdownDuration
            case .paused(let paused): return paused.totalCountdownDuration
            default: continue
            }
        }
        return activeAlarmExists ? scheduledDuration : nil
    }

    private var activeAlarmExists: Bool {
        alarms.contains { $0.state == .countdown || $0.state == .paused || $0.state == .alerting }
    }

    func remainingSeconds(at date: Date) -> TimeInterval? {
        let countdowns = presentationStates.compactMap { state -> AlarmPresentationState.Mode.Countdown? in
            if case .countdown(let countdown) = state.mode {
                return countdown
            }

            return nil
        }

        if let countdown = countdowns.min(by: { $0.fireDate < $1.fireDate }) {
            return max(0, countdown.fireDate.timeIntervalSince(date))
        }

        let pausedStates = presentationStates.compactMap { state -> AlarmPresentationState.Mode.Paused? in
            if case .paused(let paused) = state.mode {
                return paused
            }

            return nil
        }

        if let paused = pausedStates.first {
            return max(0, paused.totalCountdownDuration - paused.previouslyElapsedDuration)
        }

        if presentationStates.contains(where: {
            if case .alert = $0.mode { return true }
            return false
        }) {
            return 0
        }

        return alarmRemainingSeconds(at: date)
    }

    private func alarmRemainingSeconds(at date: Date) -> TimeInterval? {
        guard let alarm = alarms.first(where: {
            $0.state == .countdown || $0.state == .paused || $0.state == .alerting
        }) else {
            return nil
        }

        if alarm.state == .alerting {
            return 0
        }

        if case .fixed(let fireDate) = alarm.schedule {
            return max(0, fireDate.timeIntervalSince(date))
        }

        return nil
    }

    private func localizedTitle(_ text: String) -> LocalizedStringResource {
        LocalizedStringResource(String.LocalizationValue(text))
    }

}
#endif
