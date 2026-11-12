//
//  SmartiumMonitorWidget.swift
//  SmartiumWidgets
//
//  Monitor widgets. v0.12 §2: the Orb's layout and system theme, with the
//  chosen metric's ring on the plate, "CPU 37%" and "Abrir Monitor". §3.1:
//  battery is a metric too (Âmbar; Coral when low; "—" with a full ring on a
//  Mac without one). §4: Lock Screen (circular, rectangular, inline).
//  Values are the app's last sample; GPU stays simulated on iOS.
//

import AppIntents
import SwiftUI
import WidgetKit

struct SmartiumMonitorConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Monitor"
    static let description = IntentDescription("Escolha a métrica do widget.")

    @Parameter(title: "Métrica", default: .pinned)
    var metric: SmartiumMonitorMetricChoice

    init() {}
}

/// The metric choice. `pinned` follows the metric pinned in the app (v0.6);
/// the others keep `StWidgetMetric`'s raw values, so widgets configured
/// before an option existed keep their metric. `battery` is new in v0.12.
enum SmartiumMonitorMetricChoice: String, AppEnum {
    case pinned, cpu, gpu, memory, disk, battery

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Métrica"
    static let caseDisplayRepresentations: [SmartiumMonitorMetricChoice: DisplayRepresentation] = [
        .pinned: "Fixada no app",
        .cpu: "CPU",
        .gpu: "GPU",
        .memory: "RAM",
        .disk: "Disco",
        .battery: "Bateria",
    ]

    var metric: StWidgetMetric {
        StWidgetMetric(rawValue: rawValue) ?? StLiveSurfaces.pinnedWidgetMetric
    }
}

struct SmartiumMonitorEntry: TimelineEntry {
    let date: Date
    let metrics: StMetricsSnapshot
    let metric: StWidgetMetric
}

struct SmartiumMonitorProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SmartiumMonitorEntry {
        SmartiumMonitorEntry(date: .now, metrics: .placeholder, metric: .cpu)
    }

    func snapshot(for configuration: SmartiumMonitorConfiguration, in context: Context) async -> SmartiumMonitorEntry {
        entry(for: configuration)
    }

    /// Re-reads the app's last sample every 15 minutes.
    func timeline(for configuration: SmartiumMonitorConfiguration, in context: Context) async -> Timeline<SmartiumMonitorEntry> {
        Timeline(entries: [entry(for: configuration)], policy: .after(.now.addingTimeInterval(15 * 60)))
    }

    private func entry(for configuration: SmartiumMonitorConfiguration) -> SmartiumMonitorEntry {
        SmartiumMonitorEntry(
            date: .now,
            metrics: StLiveSurfaces.metrics ?? .placeholder,
            metric: configuration.metric.metric
        )
    }
}

struct SmartiumMonitorWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: StLiveSurfaces.monitorWidgetKind,
            intent: SmartiumMonitorConfiguration.self,
            provider: SmartiumMonitorProvider()
        ) { entry in
            SmartiumMonitorWidgetView(entry: entry)
                .widgetURL(StTool.monitor.deepLink)
        }
        .configurationDisplayName("Monitor")
        .description("CPU, GPU, RAM, disco ou bateria.")
        .supportedFamilies(Self.families)
    }

    static var families: [WidgetFamily] {
        #if os(iOS)
        [.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline]
        #else
        [.systemSmall, .systemMedium]
        #endif
    }
}

/// The metric as the widgets show it.
struct SmartiumMetricReading {
    let metric: StWidgetMetric
    let metrics: StMetricsSnapshot

    /// 0–1, or nil for the battery of a Mac without one.
    var value: Double? {
        metrics.value(metric).map { min(max($0, 0), 1) }
    }

    var percent: Int? {
        value.map { Int(($0 * 100).rounded()) }
    }

    /// "37%", or "—".
    var percentText: String {
        percent.map { "\($0)%" } ?? "—"
    }

    /// Ring fill: full without a value.
    var fraction: Double { value ?? 1 }

    /// Identity color; the battery turns Coral when low (§3.1).
    var color: Color {
        metric == .battery && metrics.isBatteryLow ? StTool.voice.tone : metric.rgb.color
    }

    /// "8 núcleos · ao vivo a cada 2 s".
    var caption: String {
        var parts: [String] = []
        switch metric {
        case .cpu:
            if let cores = metrics.cores { parts.append("\(cores) núcleos") }
        case .battery:
            if metrics.battery == nil {
                parts.append("Na tomada")
            } else {
                parts.append(metrics.batteryCharging == true ? "Carregando" : "Na bateria")
            }
        case .gpu:
            parts.append("Estimado")
        case .memory, .disk:
            break
        }
        if let interval = metrics.interval {
            parts.append("ao vivo a cada \(Self.seconds(interval))")
        } else {
            parts.append("atualizado às \(metrics.updatedAt.formatted(date: .omitted, time: .shortened))")
        }
        return parts.joined(separator: " · ")
    }

    private static func seconds(_ value: Double) -> String {
        let text = value.rounded() == value
            ? String(Int(value))
            : String(format: "%.1f", value).replacingOccurrences(of: ".", with: ",")
        return text + " s"
    }
}

struct SmartiumMonitorWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme
    let entry: SmartiumMonitorEntry

    private let tool = StTool.monitor
    private var reading: SmartiumMetricReading {
        SmartiumMetricReading(metric: entry.metric, metrics: entry.metrics)
    }

    var body: some View {
        switch family {
        #if os(iOS)
        case .accessoryCircular, .accessoryRectangular, .accessoryInline:
            StMonitorComplication(metric: entry.metric, metrics: entry.metrics)
        #endif
        case .systemMedium:
            medium.stWidgetBackground(tool.tone)
        default:
            small.stWidgetBackground(tool.tone)
        }
    }

    private var medium: some View {
        StWidgetMediumLayout(
            tone: tool.tone,
            systemImage: tool.systemImage,
            brand: "Monitor",
            title: Text("\(reading.metric.label) \(reading.percentText)"),
            caption: Text(reading.caption)
        ) {
            ring(lineWidth: 7, size: 20)
        } actions: {
            Link(destination: StTool.monitor.deepLink) {
                StWidgetCapsule(title: "Abrir Monitor", systemImage: "arrow.up.forward", tone: tool.tone)
            }
        }
    }

    private var small: some View {
        StWidgetSmallLayout(label: Text(reading.metric.label)) {
            Link(destination: StTool.monitor.deepLink) {
                StWidgetRoundButton(systemImage: "arrow.up.forward", tone: tool.tone)
            }
            .accessibilityLabel("Abrir Monitor")
        } element: {
            ring(lineWidth: 6, size: 17)
        }
    }

    private func ring(lineWidth: CGFloat, size: CGFloat) -> some View {
        let primary = StWidgetTheme(colorScheme).primary
        let isLowBattery = reading.metric == .battery && entry.metrics.isBatteryLow
        return StWidgetRing(fraction: reading.fraction, color: reading.color, lineWidth: lineWidth) {
            StBigNumber(
                reading.percentText,
                size: size,
                color: isLowBattery ? reading.color : primary,
                unitColor: primary
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(reading.metric.label) \(reading.percentText)")
    }
}

