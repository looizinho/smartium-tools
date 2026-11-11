//
//  SmartiumDevicesWidget.swift
//  SmartiumWidgets
//
//  Dispositivos widget (handoff v0.12 §3.2): the batteries of the iPhone,
//  the Apple Watch and the Mac as concentric rings, in the Orb's layout and
//  system theme (§2). The app copies the list from `StDeviceSync` to the App
//  Group, since the extension can't read the key-value store. §4: Lock Screen
//  (circular, rectangular, inline). Opens the Monitor.
//

import SwiftUI
import WidgetKit

struct SmartiumDevicesEntry: TimelineEntry {
    let date: Date
    let devices: [StDeviceBattery]
}

struct SmartiumDevicesProvider: TimelineProvider {
    func placeholder(in context: Context) -> SmartiumDevicesEntry {
        SmartiumDevicesEntry(date: .now, devices: Self.sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (SmartiumDevicesEntry) -> Void) {
        let devices = StLiveSurfaces.devices
        completion(SmartiumDevicesEntry(date: .now, devices: devices.isEmpty && context.isPreview ? Self.sample : devices))
    }

    /// The app reloads on every change; the timeline re-reads every 15 minutes.
    func getTimeline(in context: Context, completion: @escaping (Timeline<SmartiumDevicesEntry>) -> Void) {
        let entry = SmartiumDevicesEntry(date: .now, devices: StLiveSurfaces.devices)
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(15 * 60))))
    }

    /// Gallery preview: 82 · 64 · 41.
    static let sample: [StDeviceBattery] = [
        StDeviceBattery(id: "iphone", kind: .iphone, name: "iPhone", level: 0.82, isCharging: false, updatedAt: .now),
        StDeviceBattery(id: "watch", kind: .watch, name: "Apple Watch", level: 0.64, isCharging: false, updatedAt: .now),
        StDeviceBattery(id: "mac", kind: .mac, name: "MacBook Pro", level: 0.41, isCharging: true, updatedAt: .now),
    ]
}

struct SmartiumDevicesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: StLiveSurfaces.devicesWidgetKind, provider: SmartiumDevicesProvider()) { entry in
            SmartiumDevicesWidgetView(entry: entry)
                .widgetURL(StTool.monitor.deepLink)
        }
        .configurationDisplayName("Dispositivos")
        .description("Bateria do iPhone, do Apple Watch e do Mac.")
        .supportedFamilies(SmartiumMonitorWidget.families)
    }
}

/// Short device names for the widgets: "iPhone", "Watch", "Mac".
extension StDeviceBattery {
    var shortName: String {
        switch kind {
        case .iphone: name
        case .watch: "Watch"
        case .mac: "Mac"
        }
    }

    /// SF Symbol for the places that can't draw `StDeviceIcon` (inline).
    var symbolName: String {
        switch kind {
        case .iphone: "iphone"
        case .watch: "applewatch"
        case .mac: "laptopcomputer"
        }
    }
}

struct SmartiumDevicesWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme
    let entry: SmartiumDevicesEntry

    private let tool = StTool.monitor

    /// One device per kind, iPhone first, as in the rings.
    private var devices: [StDeviceBattery] {
        StDeviceList.ringDevices(entry.devices)
    }

    var body: some View {
        switch family {
        #if os(iOS)
        case .accessoryCircular, .accessoryRectangular, .accessoryInline:
            SmartiumDevicesAccessoryView(devices: devices)
        #endif
        case .systemMedium:
            medium.stWidgetBackground(tool.tone)
        default:
            small.stWidgetBackground(tool.tone)
        }
    }

    private var rings: some View {
        StDeviceRingsMark(devices: entry.devices, track: StWidgetTheme(colorScheme).track)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(devices.map { $0.spoken(isThisDevice: false) }.joined(separator: "; "))
    }

    private var medium: some View {
        let first = devices.first
        let others = devices.dropFirst()
            .map { "\($0.shortName) \($0.percentText)" }
            .joined(separator: " · ")
        return StWidgetMediumLayout(
            tone: tool.tone,
            systemImage: "battery.75percent",
            brand: "Dispositivos",
            title: Text(first.map { "\($0.shortName) \($0.percentText)" } ?? "Sem dispositivos"),
            caption: Text(others.isEmpty ? "Abra o app para ler as baterias." : others)
        ) {
            rings
        } actions: {
            Link(destination: StTool.monitor.deepLink) {
                StWidgetCapsule(title: "Abrir Dispositivos", systemImage: "arrow.up.forward", tone: tool.tone)
            }
        }
    }

    private var small: some View {
        let label = devices.map { $0.percent.map(String.init) ?? "—" }.joined(separator: " · ")
        return StWidgetSmallLayout(label: Text(label.isEmpty ? "Dispositivos" : label)) {
            Link(destination: StTool.monitor.deepLink) {
                StWidgetRoundButton(systemImage: "arrow.up.forward", tone: tool.tone)
            }
            .accessibilityLabel("Abrir Dispositivos")
        } element: {
            rings
        }
    }
}

// MARK: - Lock Screen (§4)

#if os(iOS)
/// Monochrome: the iPhone's ring, three rows of bars, or one line.
private struct SmartiumDevicesAccessoryView: View {
    let devices: [StDeviceBattery]
    @Environment(\.widgetFamily) private var family

    /// The iPhone, or the first device there is.
    private var main: StDeviceBattery? {
        devices.first { $0.kind == .iphone } ?? devices.first
    }

    var body: some View {
        content.containerBackground(for: .widget) { Color.clear }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryCircular:
            if let main {
                Gauge(value: main.ringFraction) {
                    StDeviceIcon(kind: main.kind, size: 12, color: .primary)
                } currentValueLabel: {
                    VStack(spacing: 0) {
                        StDeviceIcon(kind: main.kind, size: 11, color: .primary)
                            .opacity(0.7)
                        Text(main.percentText)
                            .minimumScaleFactor(0.5)
                    }
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .widgetAccentable()
                .accessibilityLabel(main.spoken(isThisDevice: false))
            } else {
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: "battery.75percent")
                }
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 3) {
                ForEach(devices) { device in
                    HStack(spacing: 6) {
                        StDeviceIcon(kind: device.kind, size: 13, color: .primary)
                        ProgressView(value: device.ringFraction)
                            .progressViewStyle(.linear)
                            .widgetAccentable()
                        Text(device.percentText)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .frame(minWidth: 34, alignment: .trailing)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(device.spoken(isThisDevice: false))
                }
                if devices.isEmpty {
                    Text("Sem dispositivos")
                        .font(.system(size: 13, weight: .semibold))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            if let main {
                Label("\(main.shortName) \(main.percentText)", systemImage: main.symbolName)
            } else {
                Label("Dispositivos", systemImage: "battery.75percent")
            }
        }
    }
}
#endif
