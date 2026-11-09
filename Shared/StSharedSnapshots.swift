//
//  StSharedSnapshots.swift
//  SmartiumTools
//
//  Snapshot types written by the app (handoff v0.5) and read by the widget
//  extension and, through WatchConnectivity, by the watch app (v0.10):
//  `StTimerSnapshot`, `StMetricsSnapshot`, `StWidgetMetric` and
//  `StToolDestination` with its deep links. Moved from SmartiumLiveSurfaces.
//

import AppIntents
import Foundation

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
    /// Battery level, 0–1 (v0.10). Optional so older data still decodes.
    var battery: Double? = nil

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
nonisolated enum StToolDestination: String, AppEnum, Codable, Sendable {
    case orb, voice, timer, staging, monitor, form

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Ferramenta"
    static let caseDisplayRepresentations: [StToolDestination: DisplayRepresentation] = [
        .orb: "Orb",
        .voice: "Voz",
        .timer: "Timer",
        .staging: "Staging",
        .monitor: "Monitor",
        .form: "Formulário",
    ]
}

// MARK: - Deep links (v0.8)

nonisolated extension StToolDestination {
    static let urlScheme = "smartium"

    /// `smartium://tool/<id>`: opens the app on this tool's tab. Live
    /// Activities, widgets and the Mac timer use it.
    var url: URL {
        URL(string: "\(Self.urlScheme)://tool/\(rawValue)")!
    }

    /// The tool in a `smartium://tool/<id>` link; nil for any other URL or
    /// an unknown id.
    init?(url: URL) {
        guard url.scheme == Self.urlScheme, url.host() == "tool",
              let id = url.pathComponents.dropFirst().first else { return nil }
        self.init(rawValue: id)
    }

    init(tool: StTool) {
        switch tool {
        case .orb: self = .orb
        case .voice: self = .voice
        case .timer: self = .timer
        case .fx: self = .staging
        case .monitor: self = .monitor
        case .form: self = .form
        }
    }
}

nonisolated extension StTool {
    /// Link that opens the app on this tool's tab (v0.8).
    var deepLink: URL {
        StToolDestination(tool: self).url
    }
}
