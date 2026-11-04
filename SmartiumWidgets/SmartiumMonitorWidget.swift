//
//  SmartiumMonitorWidget.swift
//  SmartiumWidgets
//
//  Monitor widgets (handoff v0.5): rings in each metric's identity color, no
//  labels. Values are the app's last sample; GPU stays simulated on iOS.
//

import AppIntents
import SwiftUI
import WidgetKit

struct SmartiumMonitorConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Monitor"
    static let description = IntentDescription("Escolha a métrica do widget pequeno.")

    @Parameter(title: "Métrica", default: .pinned)
    var metric: SmartiumMonitorMetricChoice

    init() {}
}

/// Small widget's metric choice. `pinned` follows the metric pinned in the
/// app (v0.6); the others keep `StWidgetMetric`'s raw values, so widgets
/// configured before this option existed keep their metric.
enum SmartiumMonitorMetricChoice: String, AppEnum {
    case pinned, cpu, gpu, memory, disk

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Métrica"
    static let caseDisplayRepresentations: [SmartiumMonitorMetricChoice: DisplayRepresentation] = [
        .pinned: "Fixada no app",
        .cpu: "CPU",
        .gpu: "GPU",
        .memory: "RAM",
        .disk: "Disco",
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
        .description("CPU, GPU, RAM e disco.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct SmartiumMonitorWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SmartiumMonitorEntry

    var body: some View {
        if family == .systemMedium {
            HStack(spacing: 0) {
                ForEach(StWidgetMetric.allCases, id: \.self) { metric in
                    ring(metric, diameter: 72, lineWidth: 7, fontSize: 17)
                        .frame(maxWidth: .infinity)
                }
            }
            .containerBackground(for: .widget) {
                SmartiumWidgetBackground(
                    stops: [
                        .init(color: StAccent.sky.color(opacity: 0.24), location: 0),
                        .init(color: StTool.orb.opacity(0.08), location: 0.6),
                        .init(color: .stInk800, location: 0.9),
                    ],
                    center: UnitPoint(x: 0.15, y: 0.1),
                    stroke: .white.opacity(0.06)
                )
            }
        } else {
            let rgb = entry.metric.rgb
            ring(entry.metric, diameter: 128, lineWidth: 11, fontSize: 30)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .containerBackground(for: .widget) {
                    SmartiumWidgetBackground(
                        stops: [
                            .init(color: rgb.color(opacity: 0.28), location: 0),
                            .init(color: rgb.color(opacity: 0), location: 0.7),
                        ],
                        center: UnitPoint(x: 0.3, y: 0.15),
                        stroke: rgb.color(opacity: 0.28)
                    )
                }
        }
    }

    /// Ring centered on the stroke radius of the prototype (r 56 in 128, r 31 in 72).
    private func ring(_ metric: StWidgetMetric, diameter: CGFloat, lineWidth: CGFloat, fontSize: CGFloat) -> some View {
        let value = min(max(entry.metrics.value(metric), 0), 1)
        let percent = Int((value * 100).rounded())
        let ringDiameter = diameter - (diameter == 128 ? 16 : 10)
        return ZStack {
            Circle()
                .stroke(.white.opacity(0.08), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: value)
                .stroke(metric.rgb.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            StBigNumber("\(percent)%", size: fontSize, unitColor: .white)
                .padding(.horizontal, lineWidth + 2)
        }
        .frame(width: ringDiameter, height: ringDiameter)
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(Text(metric.localizedStringResource)) \(percent)%"))
    }
}
