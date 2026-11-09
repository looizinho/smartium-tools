//
//  StWatchState.swift
//  SmartiumTools
//
//  What the iPhone sends to the watch app through WatchConnectivity
//  (handoff v0.10 §3). The watch is read-only: nothing flows back except a
//  "hello" asking for the current state.
//

import Foundation

nonisolated struct StWatchState: Codable, Sendable, Equatable {
    /// `tabOrder` filtered to the watch's tools: voice, timer, monitor.
    var order: [StToolDestination] = StWatchState.tools
    var voice = Voice()
    var timer = StTimerSnapshot()
    var monitor = Monitor()
    /// Last user action on one of these tools on the iPhone.
    var focus: Focus?
    var sentAt = Date.now

    /// The tools the watch shows, in their default order.
    static let tools: [StToolDestination] = [.voice, .timer, .monitor]

    struct Voice: Codable, Sendable, Equatable {
        /// `VoiceMode` raw value: dictation, translation, commands or notes.
        var mode = "dictation"
        /// Always false until the Voice tool listens for real.
        var listening = false

        var modeTitle: String {
            switch mode {
            case "translation": "Tradução"
            case "commands": "Comandos"
            case "notes": "Notas"
            default: "Ditado"
            }
        }
    }

    struct Monitor: Codable, Sendable, Equatable {
        /// `settings.monitor.pinnedMetric`: memory, disk, gpu or battery; nil
        /// shows the CPU, like the iPhone hero.
        var pinned: String?
        var snapshot: StMetricsSnapshot?
        /// Caption under the number, as on the iPhone hero ("4,8 de 7,5 GB",
        /// "Estimado", "6 núcleos"…), for the pinned metric.
        var detail = ""
    }

    struct Focus: Codable, Sendable, Equatable {
        var tool: StToolDestination
        var at: Date
    }

    /// Order for the watch: `tabOrder` ids first, then any watch tool missing
    /// from it.
    static func order(from tabOrder: [String]) -> [StToolDestination] {
        let listed = tabOrder.compactMap(StToolDestination.init(rawValue:)).filter(tools.contains)
        var seen = Set<StToolDestination>()
        let unique = listed.filter { seen.insert($0).inserted }
        return unique + tools.filter { !unique.contains($0) }
    }
}

// MARK: - Monitor metric on the watch

/// The metric the watch's Monitor page shows, with the iPhone hero's colors.
nonisolated enum StWatchMetric: String, Sendable {
    case cpu, memory, disk, gpu, battery

    init(pinned: String?) {
        self = pinned.flatMap(StWatchMetric.init(rawValue:)) ?? .cpu
    }

    var label: String {
        switch self {
        case .cpu: "CPU"
        case .memory: "Memória"
        case .disk: "Disco"
        case .gpu: "GPU"
        case .battery: "Bateria"
        }
    }

    /// Hero label color (MonitorView `heroLabelColor`; CPU uses Sky).
    var labelRGB: StRGB {
        switch self {
        case .cpu: StTool.monitor.rgb
        case .memory: StTool.orb.rgb
        case .disk: StAccent.brand
        case .gpu: StTool.timer.rgb
        case .battery: StTool.fx.rgb
        }
    }

    /// Ring color: status levels, inverted for the battery (low is the alert).
    func ringRGB(_ value: Double) -> StRGB {
        guard self == .battery else { return StStatus(fraction: value).tool.rgb }
        return value < 0.2 ? StTool.voice.rgb : value < 0.4 ? StTool.fx.rgb : StTool.timer.rgb
    }

    func value(in snapshot: StMetricsSnapshot) -> Double? {
        switch self {
        case .cpu: snapshot.cpu
        case .memory: snapshot.memory
        case .disk: snapshot.disk
        case .gpu: snapshot.gpu
        case .battery: snapshot.battery
        }
    }
}

// MARK: - Transport

nonisolated enum StWatchTransport {
    /// Key of the encoded `StWatchState` in application contexts and messages.
    static let stateKey = "state"
    /// Message key the watch sends to ask for the current state.
    static let helloKey = "hello"

    static func encode(_ state: StWatchState) -> Data? {
        try? JSONEncoder().encode(state)
    }

    static func decode(_ payload: [String: Any]) -> StWatchState? {
        guard let data = payload[stateKey] as? Data else { return nil }
        return try? JSONDecoder().decode(StWatchState.self, from: data)
    }
}
