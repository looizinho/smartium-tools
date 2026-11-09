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
        #elseif os(macOS)
        // v0.7: the Mac has its own timer, without AlarmKit.
        MacTimerView()
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

/// Timer limits (v0.4): the tool is for events and talks, so 2 h at most.
nonisolated enum StTimer {
    static let maxDuration: TimeInterval = 7_200
}

/// Timer hero: Menta progress ring, Sky tick ring, label + clock + status.
/// The clock is a white `StBigNumber` without glow (v0.3), at 20% of the hero
/// for mm:ss and 14% for h:mm:ss so it stays inside the ring (v0.4).
struct StTimerRing: View {
    let size: CGFloat
    /// Remaining fraction, 0–1.
    let fraction: Double
    let label: String
    let clock: String
    let status: String

    var body: some View {
        let timer = StTool.timer
        let sky = StAccent.sky
        StDialRing(
            size: size,
            fraction: fraction,
            ringColor: timer.tone,
            trackColor: timer.opacity(0.14),
            tickColor: sky.color(opacity: 0.45),
            halo: [
                .init(color: timer.opacity(0.22), location: 0),
                .init(color: sky.color(opacity: 0.08), location: 0.5),
                .init(color: timer.opacity(0), location: 0.7)
            ]
        ) {
            VStack(spacing: 2) {
                Text(label)
                    .font(.stTag)
                    .tracking(1.4)
                    .foregroundStyle(sky.color)
                StBigNumber(clock, size: (size * (clock.count > 5 ? 0.14 : 0.2)).rounded())
                Text(status)
                    .font(StFont.body(13))
                    .foregroundStyle(Color.stTextPrimary.opacity(0.55))
            }
            .accessibilityElement(children: .combine)
        }
    }
}

/// Clock text: `mm:ss`, or `h:mm:ss` from 1 h.
nonisolated enum TimerFormat {
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

/// Timer adjustments (v0.3 "ATALHOS"): add or remove time, no selected state.
struct TimerAdjustment: Hashable {
    let seconds: Int
    let color: StRGB

    var title: String {
        (seconds > 0 ? "+" : "−") + "\(abs(seconds) / 60) min"
    }

    static let all: [TimerAdjustment] = [
        TimerAdjustment(seconds: 60, color: StTool.timer.rgb),
        TimerAdjustment(seconds: 300, color: StAccent.sky),
        TimerAdjustment(seconds: 600, color: StTool.orb.rgb),
        TimerAdjustment(seconds: -60, color: StTool.fx.rgb),
        TimerAdjustment(seconds: -300, color: StTool.voice.rgb),
        TimerAdjustment(seconds: -600, color: StAccent.brand)
    ]
}

#if canImport(AlarmKit) && os(iOS)

private struct AlarmKitViewContent: View {
    @State private var manager = AlarmKitManager()
    @State private var selectedHours = 0
    @State private var selectedMinutes = 5
    @State private var selectedSeconds = 0
    @State private var limitimerSettings = LimitimerSettings()
    /// The recent row swiped open, if any.
    @State private var openRecentID: LimitimerRecent.ID?
    @Environment(\.stIsActiveTab) private var isActiveTab

    private func timerRing(size: CGFloat, at date: Date) -> some View {
        let remaining = manager.remainingSeconds(at: date)
        let total = manager.totalDuration ?? selectedDuration
        return StTimerRing(
            size: size,
            fraction: remaining.map { total > 0 ? $0 / total : 0 } ?? 1,
            label: remaining == nil ? "DEFINIDO" : "RESTANTE",
            clock: TimerFormat.duration(remaining ?? selectedDuration),
            status: ringStatus
        )
    }

    var body: some View {
        // The hero shows only while a timer runs or is paused (v0.4, iPhone).
        let isActive = activeAlarm?.state == .countdown || activeAlarm?.state == .paused
        StAdaptiveToolLayout(tool: .timer, tag: "Timer", showsHero: isActive) { size in
            // Hidden iOS tab (v0.9.4): no 1 s clock; the ring is redrawn on return.
            if isActiveTab {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    timerRing(size: size, at: context.date)
                }
            } else {
                timerRing(size: size, at: .now)
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
                items: TimerAdjustment.all,
                label: \.title,
                color: \.color,
                isOn: { _ in false },
                select: adjust
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
        // Any tap elsewhere closes an open recent row.
        .simultaneousGesture(TapGesture().onEnded { closeRecent() }, including: openRecentID == nil ? .subviews : .all)
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
        // At 2 h, minutes and seconds lock at 0 (StTimer.maxDuration).
        let isAtMaxHours = selectedHours == Int(StTimer.maxDuration) / 3_600
        return HStack(spacing: 0) {
            picker(selection: $selectedHours, range: 0...(Int(StTimer.maxDuration) / 3_600), label: "Horas")
            picker(selection: $selectedMinutes, range: isAtMaxHours ? 0...0 : 0...59, label: "Minutos")
            picker(selection: $selectedSeconds, range: isAtMaxHours ? 0...0 : 0...59, label: "Segundos")
        }
        .onChange(of: isAtMaxHours) { _, isAtMax in
            if isAtMax {
                selectedMinutes = 0
                selectedSeconds = 0
            }
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
                    .font(StFont.body(21))
                    .monospacedDigit()
                    .tag(value)
            }
        }
        .pickerStyle(.wheel)
        .labelsHidden()
        .frame(width: 104, height: 150)
        .clipped()
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
                .font(StFont.body(17, .semibold))
                .foregroundStyle(sky.color)
                .frame(width: 38, height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(sky.color(opacity: 0.16))
                )
                .accessibilityHidden(true)
            TextField("Mensagem de encerramento", text: $limitimerSettings.endMessage)
                .font(StFont.body(16, .medium))
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
                .font(StFont.body(20, .bold))
                .padding(.top, 8)
                .padding(.horizontal, 4)
                .accessibilityAddTraits(.isHeader)

            ForEach(Array(limitimerSettings.recents.enumerated()), id: \.element.id) { index, recent in
                StSwipeToDelete(
                    isOpen: Binding(
                        get: { openRecentID == recent.id },
                        set: { openRecentID = $0 ? recent.id : nil }
                    ),
                    onDelete: { deleteRecent(recent) }
                ) {
                    recentRow(recent, color: [StAccent.sky, StTool.voice.rgb, StTool.fx.rgb, StTool.orb.rgb][index % 4])
                }
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func recentRow(_ recent: LimitimerRecent, color: StRGB) -> some View {
        let shape = RoundedRectangle(cornerRadius: StRadius.row, style: .continuous)
        return HStack(alignment: .center, spacing: 14) {
            Image(systemName: "timer")
                .font(StFont.body(19, .semibold))
                .foregroundStyle(color.color)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(color.color(opacity: 0.16))
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                StBigNumber(TimerFormat.duration(recent.duration), size: 24)

                Text(recent.message.isEmpty ? "Sem mensagem" : recent.message)
                    .font(StFont.body(13))
                    .foregroundStyle(Color.stTextPrimary.opacity(0.55))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button {
                applyDuration(Int(recent.duration))
                startTimer(duration: recent.duration, message: recent.message)
            } label: {
                Image(systemName: "play.fill")
                    .font(StFont.body(15, .bold))
                    .foregroundStyle(StTool.timer.tone)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(StTool.timer.opacity(0.16)))
            }
            .buttonStyle(StPressStyle())
            .focusEffectDisabled()
            .accessibilityLabel("Iniciar \(TimerFormat.duration(recent.duration))")
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(Color.stInk800))
        .overlay(shape.strokeBorder(.white.opacity(0.05), lineWidth: 1))
    }

    /// Stopped: changes the set time (0…2:00:00). Running or paused: changes
    /// the remaining time without stopping, up to 2:00:00; reaching 0 resets
    /// the timer.
    private func adjust(_ adjustment: TimerAdjustment) {
        guard let activeAlarm else {
            applyDuration(Int(selectedDuration) + adjustment.seconds)
            return
        }
        guard activeAlarm.state != .alerting else { return }
        Task {
            await manager.adjust(activeAlarm, by: TimeInterval(adjustment.seconds))
        }
    }

    private func deleteRecent(_ recent: LimitimerRecent) {
        withAnimation(.easeInOut(duration: 0.25)) {
            limitimerSettings = limitimerSettings.removingRecent(id: recent.id)
            openRecentID = nil
        }
        saveTimerSettings()
    }

    private func closeRecent() {
        guard openRecentID != nil else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            openRecentID = nil
        }
    }

    /// Sets the picker, clamped to 0…`StTimer.maxDuration`.
    private func applyDuration(_ seconds: Int) {
        let seconds = min(Int(StTimer.maxDuration), max(0, seconds))
        selectedHours = seconds / 3_600
        selectedMinutes = (seconds % 3_600) / 60
        selectedSeconds = seconds % 60
    }

    private func startTimer(duration: TimeInterval? = nil, message: String? = nil) {
        // Recents saved before v0.4 may be longer than the limit.
        let timerDuration = min(duration ?? selectedDuration, StTimer.maxDuration)
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
    /// Ring total after live adjustments; nil uses AlarmKit's total.
    private(set) var ringTotalOverride: TimeInterval?
    private var lastMessage = ""
    private var lastTint = StTool.timer.tone
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

    /// `ringTotal` keeps the ring's total across live adjustments;
    /// `startPaused` reschedules a paused timer without resuming it.
    func scheduleTimer(
        duration: TimeInterval,
        tint: Color,
        message: String,
        ringTotal: TimeInterval? = nil,
        startPaused: Bool = false
    ) async {
        isWorking = true
        defer { isWorking = false }

        do {
            try await StTimerService.schedule(
                duration: duration,
                message: message,
                tint: tint,
                startPaused: startPaused
            )
            // Adjustments pass `ringTotal`; only a fresh start sets what widgets restart with.
            if ringTotal == nil {
                StTimerService.recordStart(duration: duration, message: message)
            }
            scheduledDuration = duration
            ringTotalOverride = ringTotal
            lastMessage = message
            lastTint = tint
            refresh()
        } catch {
            authorizationState = AlarmManager.shared.authorizationState
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

    /// AlarmKit can't change a scheduled timer, so an adjustment replaces it:
    /// cancel, then schedule the new remaining time (paused if it was paused).
    /// Adding past the original total grows the ring's total with it.
    func adjust(_ alarm: Alarm, by delta: TimeInterval) async {
        guard let remaining = remainingSeconds(at: .now) else { return }
        let total = totalDuration ?? remaining
        let newRemaining = min((remaining + delta).rounded(.up), StTimer.maxDuration)
        // Already at the limit: nothing to reschedule.
        guard newRemaining != remaining.rounded(.up) else { return }
        let wasPaused = alarm.state == .paused
        cancel(alarm)
        guard newRemaining > 0 else {
            ringTotalOverride = nil
            return
        }
        await scheduleTimer(
            duration: newRemaining,
            tint: lastTint,
            message: lastMessage,
            ringTotal: max(total, newRemaining),
            startPaused: wasPaused
        )
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
        publishSnapshot()
    }

    /// Keeps the Timer widgets and control in step with this screen.
    private func publishSnapshot() {
        let alarm = alarms.first {
            $0.state == .countdown || $0.state == .paused || $0.state == .alerting
        }
        StTimerService.publish(
            state: alarm?.state,
            remaining: remainingSeconds(at: .now),
            total: totalDuration
        )
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
        if let ringTotalOverride, activeAlarmExists {
            return ringTotalOverride
        }
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

}
#endif
