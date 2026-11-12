//
//  SmartiumDevicesWidget.swift
//  SmartiumWidgets
//
//  Dispositivos widget (handoff v0.12 §3.2): the batteries of the iPhone,
//  the Apple Watch and the Mac as concentric rings, in the Orb's layout and
//  system theme (§2). The app copies the list from `StDeviceSync` to the App
//  Group, since the extension can't read the key-value store. §4: Lock Screen
//  (circular, rectangular, inline). Opens the Monitor.
//  v0.12.3: the user picks the devices (`SmartiumDevicesConfiguration`),
//  and a single device gets its own layout: one large ring with the icon and
//  the percent.
//

import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Configuration (v0.12.3 §1)

struct SmartiumDevicesConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Dispositivos"
    static let description = IntentDescription("Escolha os aparelhos do widget.")

    /// On by default, so widgets placed before v0.12.3 keep showing every device.
    @Parameter(title: "Seleção automática", default: true)
    var isAutomatic: Bool

    @Parameter(title: "Aparelhos")
    var devices: [StDeviceEntity]?

    static var parameterSummary: some ParameterSummary {
        When(\.$isAutomatic, .equalTo, false) {
            Summary {
                \.$isAutomatic
                \.$devices
            }
        } otherwise: {
            Summary {
                \.$isAutomatic
            }
        }
    }

    init() {}
}

/// A device from the App Group list (`StLiveSurfaces.devices`). The id is the
/// installation's UUID, so the choice survives a rename (§1.1).
struct StDeviceEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Aparelho"
    static let defaultQuery = StDeviceEntityQuery()

    let id: String
    let name: String
    let kind: StDeviceBattery.Kind?

    init(_ device: StDeviceBattery) {
        id = device.id
        name = device.name
        kind = device.kind
    }

    /// A chosen device that left the list: the choice stays stored, and the
    /// widget simply doesn't draw it.
    init(missingID id: String) {
        self.id = id
        name = "Aparelho indisponível"
        kind = nil
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(kind?.typeName ?? "Não aparece mais")")
    }
}

struct StDeviceEntityQuery: EntityQuery {
    init() {}

    func entities(for identifiers: [String]) async throws -> [StDeviceEntity] {
        let known = StLiveSurfaces.devices
        return identifiers.map { id in
            known.first { $0.id == id }.map(StDeviceEntity.init) ?? StDeviceEntity(missingID: id)
        }
    }

    /// Every known device, so the editor's list shows up ready.
    func suggestedEntities() async throws -> [StDeviceEntity] {
        StLiveSurfaces.devices.map(StDeviceEntity.init)
    }
}

extension StDeviceBattery.Kind {
    /// The device type, under the name in the widget editor.
    var typeName: String {
        switch self {
        case .iphone: "iPhone"
        case .watch: "Apple Watch"
        case .mac: "Mac"
        }
    }
}

struct SmartiumDevicesEntry: TimelineEntry {
    let date: Date
    /// What the widget draws, outer ring first. Automatic: every known
    /// device, one ring per kind. Chosen: up to three, in the chosen order,
    /// leaving out the ones that are gone.
    let devices: [StDeviceBattery]
    /// The user's own choice: rings by position, not by kind (§1).
    let isChosen: Bool

    init(date: Date, devices: [StDeviceBattery], isChosen: Bool = false) {
        self.date = date
        self.devices = isChosen ? Array(devices.prefix(3)) : StDeviceList.ringDevices(devices)
        self.isChosen = isChosen
    }
}

struct SmartiumDevicesProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SmartiumDevicesEntry {
        SmartiumDevicesEntry(date: .now, devices: Self.sample)
    }

    func snapshot(for configuration: SmartiumDevicesConfiguration, in context: Context) async -> SmartiumDevicesEntry {
        if StLiveSurfaces.devices.isEmpty && context.isPreview {
            return SmartiumDevicesEntry(date: .now, devices: Self.sample)
        }
        return entry(for: configuration)
    }

    /// The app reloads on every change; the timeline re-reads every 15 minutes.
    func timeline(for configuration: SmartiumDevicesConfiguration, in context: Context) async -> Timeline<SmartiumDevicesEntry> {
        Timeline(entries: [entry(for: configuration)], policy: .after(.now.addingTimeInterval(15 * 60)))
    }

    private func entry(for configuration: SmartiumDevicesConfiguration) -> SmartiumDevicesEntry {
        let known = StLiveSurfaces.devices
        guard !configuration.isAutomatic else {
            return SmartiumDevicesEntry(date: .now, devices: known)
        }
        let chosen = (configuration.devices ?? []).compactMap { choice in
            known.first { $0.id == choice.id }
        }
        return SmartiumDevicesEntry(date: .now, devices: chosen, isChosen: true)
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
        AppIntentConfiguration(
            kind: StLiveSurfaces.devicesWidgetKind,
            intent: SmartiumDevicesConfiguration.self,
            provider: SmartiumDevicesProvider()
        ) { entry in
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

    /// Outer ring first: iPhone, Watch, Mac, or the chosen order.
    private var devices: [StDeviceBattery] { entry.devices }

    /// Exactly one device: the single-device layout (§2).
    private var single: StDeviceBattery? {
        devices.count == 1 ? devices.first : nil
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

    @ViewBuilder
    private var rings: some View {
        let theme = StWidgetTheme(colorScheme)
        if let single {
            // §2: one large ring in the device color (r 44, stroke 7), with
            // the icon and the percent inside.
            ZStack {
                StDeviceRingsMark(devices: [single], track: theme.track, byPosition: true)
                VStack(spacing: 2) {
                    StDeviceIcon(kind: single.kind, size: 16, color: single.rgb.color)
                    HStack(spacing: 2) {
                        StBigNumber(single.percentText, size: 17, color: single.isLow ? single.levelRGB.color : theme.primary)
                        if single.isCharging {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(StTool.timer.tone)
                        }
                    }
                }
                .padding(.horizontal, 14)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(single.spoken(isThisDevice: false))
        } else {
            StDeviceRingsMark(devices: devices, track: theme.track, byPosition: entry.isChosen)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(devices.map { $0.spoken(isThisDevice: false) }.joined(separator: "; "))
        }
    }

    private var medium: some View {
        let first = devices.first
        let caption: String
        if let single {
            caption = single.stateText
        } else {
            let others = devices.dropFirst()
                .map { "\($0.shortName) \($0.percentText)" }
                .joined(separator: " · ")
            caption = others.isEmpty ? "Abra o app para ler as baterias." : others
        }
        return StWidgetMediumLayout(
            tone: tool.tone,
            systemImage: "battery.75percent",
            brand: "Dispositivos",
            title: Text(first.map { "\(single == nil ? $0.shortName : $0.name) \($0.percentText)" } ?? "Sem dispositivos"),
            caption: Text(caption)
        ) {
            rings
        } actions: {
            Link(destination: StTool.monitor.deepLink) {
                StWidgetCapsule(title: "Abrir Dispositivos", systemImage: "arrow.up.forward", tone: tool.tone)
            }
        }
    }

    private var small: some View {
        let label: String
        if let single {
            label = single.name
        } else {
            let percents = devices.map { $0.percent.map(String.init) ?? "—" }.joined(separator: " · ")
            label = percents.isEmpty ? "Sem dispositivos" : percents
        }
        return StWidgetSmallLayout(label: Text(label)) {
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
/// Monochrome: the first device's ring, up to three rows of bars, or one
/// line. v0.12.3 §3: the first of the widget's devices (the iPhone when the
/// choice is automatic, since it comes first).
private struct SmartiumDevicesAccessoryView: View {
    let devices: [StDeviceBattery]
    @Environment(\.widgetFamily) private var family

    private var main: StDeviceBattery? {
        devices.first
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
