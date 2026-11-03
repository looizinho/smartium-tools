//
//  SmartiumLiveSurfaces.swift
//  SmartiumTools
//
//  App Group snapshots read by the Control Center controls and the Timer and
//  Monitor widgets (handoff v0.5). The app writes them; the widget extension
//  only reads them.
//

import AppIntents
import Foundation
import SwiftUI
#if canImport(WidgetKit)
import WidgetKit
#endif

nonisolated enum StLiveSurfaces {
    static let timerWidgetKind = "SmartiumTimerWidget"
    static let monitorWidgetKind = "SmartiumMonitorWidget"

    enum ControlKind {
        static let orb = "dev.smartium.tools.control.orb"
        static let voice = "dev.smartium.tools.control.voice"
        static let timer = "dev.smartium.tools.control.timer"
        static let staging = "dev.smartium.tools.control.staging"
        static let monitor = "dev.smartium.tools.control.monitor"
    }

    private enum Key {
        static let timer = "dev.smartium.tools.timerSnapshot"
        static let metrics = "dev.smartium.tools.metricsSnapshot"
        static let orbActivity = "dev.smartium.tools.orbActivityActive"
        static let pendingTool = "dev.smartium.tools.pendingTool"
    }

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: ToolSharedState.appGroupIdentifier) ?? .standard
    }

    // MARK: Timer

    static var timer: StTimerSnapshot {
        get { read(Key.timer) ?? StTimerSnapshot() }
        set { write(newValue, Key.timer) }
    }

    // MARK: Monitor

    static var metrics: StMetricsSnapshot? {
        get { read(Key.metrics) }
        set { write(newValue, Key.metrics) }
    }

    // MARK: Orb

    /// Whether the Orb's Live Activity is running, as last seen by the app.
    static var isOrbActivityActive: Bool {
        get { defaults.bool(forKey: Key.orbActivity) }
        set { defaults.set(newValue, forKey: Key.orbActivity) }
    }

    // MARK: Navigation

    /// Tab an intent asked the app to open; the app consumes it on activation.
    static func requestTool(_ destination: StToolDestination) {
        defaults.set(destination.rawValue, forKey: Key.pendingTool)
    }

    static func takePendingTool() -> StToolDestination? {
        guard let raw = defaults.string(forKey: Key.pendingTool) else { return nil }
        defaults.removeObject(forKey: Key.pendingTool)
        return StToolDestination(rawValue: raw)
    }

    // MARK: Reload

    static func reloadTimer() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: timerWidgetKind)
        reloadControl(ControlKind.timer)
        #endif
    }

    static func reloadMonitor() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: monitorWidgetKind)
        reloadControl(ControlKind.monitor)
        #endif
    }

    static func reloadControl(_ kind: String) {
        #if canImport(WidgetKit) && os(iOS)
        ControlCenter.shared.reloadControls(ofKind: kind)
        #endif
    }

    private static func read<Value: Decodable>(_ key: String) -> Value? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(Value.self, from: $0) }
    }

    private static func write<Value: Encodable>(_ value: Value?, _ key: String) {
        guard let value, let data = try? JSONEncoder().encode(value) else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(data, forKey: key)
    }
}

extension Notification.Name {
    /// Posted in the app process after an intent asks for a tab.
    static let smartiumOpenToolRequested = Notification.Name("dev.smartium.tools.openToolRequested")
}

// MARK: - Timer snapshot

/// The single Limitimer timer as last written by the app.
nonisolated struct StTimerSnapshot: Codable, Sendable, Equatable {
    enum Phase: String, Codable, Sendable {
        case idle, running, paused, alerting
    }

    var phase: Phase = .idle
    /// End of the countdown while running.
    var fireDate: Date?
    /// Remaining seconds while paused.
    var pausedRemaining: TimeInterval?
    /// Ring total, including live adjustments.
    var total: TimeInterval?
    /// Duration a start from a widget or control uses.
    var lastDuration: TimeInterval = 300
    var message: String = ""

    /// The phase at `date`: a countdown past its end shows as finished.
    func phase(at date: Date) -> Phase {
        if phase == .running, let fireDate, fireDate <= date { return .idle }
        return phase
    }

    func remaining(at date: Date) -> TimeInterval {
        switch phase(at: date) {
        case .running: max(0, (fireDate ?? date).timeIntervalSince(date))
        case .paused: max(0, pausedRemaining ?? 0)
        case .idle, .alerting: 0
        }
    }

    /// `mm:ss`, or `h:mm:ss` from one hour.
    static func format(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let rest = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, rest)
            : String(format: "%02d:%02d", minutes, rest)
    }
}

// MARK: - Metrics snapshot

/// Last Monitor sample, as 0–1 fractions.
nonisolated struct StMetricsSnapshot: Codable, Sendable, Equatable {
    var cpu: Double
    var gpu: Double
    var memory: Double
    var disk: Double
    var updatedAt: Date

    func value(_ metric: StWidgetMetric) -> Double {
        switch metric {
        case .cpu: cpu
        case .gpu: gpu
        case .memory: memory
        case .disk: disk
        }
    }

    static let placeholder = StMetricsSnapshot(cpu: 0.32, gpu: 0.18, memory: 0.64, disk: 0.71, updatedAt: .now)
}

/// Metric shown by the small Monitor widget ("Editar widget").
nonisolated enum StWidgetMetric: String, AppEnum, CaseIterable, Sendable {
    case cpu, gpu, memory, disk

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Métrica"
    static let caseDisplayRepresentations: [StWidgetMetric: DisplayRepresentation] = [
        .cpu: "CPU",
        .gpu: "GPU",
        .memory: "RAM",
        .disk: "Disco",
    ]

    /// Identity color of the metric (not a status color).
    var rgb: StRGB {
        switch self {
        case .cpu: StAccent.sky
        case .gpu: StTool.timer.rgb
        case .memory: StTool.orb.rgb
        case .disk: StAccent.brand
        }
    }
}

// MARK: - Destinations

/// Tabs an intent can open; raw values match `ToolTab`.
nonisolated enum StToolDestination: String, AppEnum, Sendable {
    case orb, voice, timer, staging, monitor

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Ferramenta"
    static let caseDisplayRepresentations: [StToolDestination: DisplayRepresentation] = [
        .orb: "Orb",
        .voice: "Voz",
        .timer: "Timer",
        .staging: "Staging",
        .monitor: "Monitor",
    ]
}
