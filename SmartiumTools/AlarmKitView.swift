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
    @Environment(\.smartiumAppearance) private var appearance

    var body: some View {
        #if canImport(AlarmKit) && os(iOS)
        AlarmKitViewContent()
        #else
        VStack(spacing: 18) {
            Image(systemName: "timer")
                .font(.system(size: 42, weight: .medium))
                .foregroundStyle(appearance.accentColor)
                .padding(22)
                .background(
                    Circle()
                        .fill(appearance.accentColor.opacity(0.12))
                )

            Text("Área reservada para implementar alarmes com o AlarmKit.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #endif
    }
}

#if canImport(AlarmKit) && os(iOS)
private struct SmartiumAlarmMetadata: AlarmMetadata {}

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

private struct AlarmKitViewContent: View {
    @Environment(\.smartiumAppearance) private var appearance
    @State private var manager = AlarmKitManager()
    @State private var selectedHours = 0
    @State private var selectedMinutes = 5
    @State private var selectedSeconds = 0
    @State private var limitimerSettings = LimitimerSettings()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = manager.remainingSeconds(at: context.date) ?? selectedDuration

                    Text(TimerFormat.duration(remaining))
                        .font(.system(size: 52, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())
                        .animation(.snappy, value: remaining)
                        .accessibilityLabel("Tempo restante")
                }

                Spacer()

                Button {
                    startTimer()
                } label: {
                    Image(systemName: "play.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(appearance.accentColor)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(.quinary))
                }
                .disabled(selectedDuration == 0 || manager.isWorking)
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 12)

            ScrollView {
                VStack(spacing: 28) {
                    durationPicker

                    VStack(alignment: .leading, spacing: 16) {
                        TextField("Mensagem de encerramento", text: $limitimerSettings.endMessage)
                            .font(.title3.weight(.medium))
                    }
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 22)
                            .fill(.quinary)
                    )

                    if !limitimerSettings.recents.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Recentes")
                                .font(.title2.bold())
                                .padding(.bottom, 8)

                            ForEach(limitimerSettings.recents) { recent in
                                recentRow(recent)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                }
                .padding(.horizontal)
                .padding(.bottom, 24)
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

    private var durationPicker: some View {
        HStack(spacing: 0) {
            picker(selection: $selectedHours, range: 0...23, label: "horas")
            picker(selection: $selectedMinutes, range: 0...59, label: "min")
            picker(selection: $selectedSeconds, range: 0...59, label: "s")
        }
        .overlay(alignment: .center) {
            Capsule()
                .fill(.quinary)
                .frame(height: 54)
                .allowsHitTesting(false)
        }
    }

    private func picker(
        selection: Binding<Int>,
        range: ClosedRange<Int>,
        label: String
    ) -> some View {
        Picker(label, selection: selection) {
            ForEach(range, id: \.self) { value in
                Text("\(value)")
                    .tag(value)
            }
        }
        .pickerStyle(.wheel)
        .labelsHidden()
        .frame(maxWidth: .infinity)
        .overlay {
            Text(label)
                .font(.body.weight(.medium))
                .offset(x: label == "s" ? 28 : 42)
                .allowsHitTesting(false)
        }
    }

    private func recentRow(_ recent: LimitimerRecent) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(TimerFormat.duration(recent.duration))
                    .font(.system(size: 44, weight: .light, design: .rounded))
                    .foregroundStyle(.primary)

                Text(recent.message.isEmpty ? "Sem mensagem" : recent.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                applyDuration(Int(recent.duration))
                startTimer(duration: recent.duration, message: recent.message)
            } label: {
                Image(systemName: "play.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(appearance.accentColor)
                    .frame(width: 54, height: 54)
                    .background(Circle().fill(.quinary))
            }
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Divider()
        }
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

        Task {
            await manager.scheduleTimer(
                duration: timerDuration,
                tint: appearance.accentColor,
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
                tintColor: tint
            )
            let configuration = AlarmManager.AlarmConfiguration.timer(
                duration: duration,
                attributes: attributes
            )

            _ = try await AlarmManager.shared.schedule(id: UUID(), configuration: configuration)
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
