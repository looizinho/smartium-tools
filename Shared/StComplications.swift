//
//  StComplications.swift
//  SmartiumTools
//
//  The accessory families (circular, rectangular, inline) of the Timer,
//  Monitor and Dispositivos widgets, shared by the iPhone's Lock Screen and
//  the watch's complications (handoff v0.12.1 §1). One structure for all:
//
//  - Rectangular: a 44 pt glyph on the left (a ring when there is progress,
//    with the icon inside) and two lines on the right, the tool's name at
//    13 pt semibold and the value at 17 pt bold.
//  - Circular: a capacity gauge with the icon above and a short value below.
//  - Inline: icon and "Timer · 4:12".
//
//  One color rule, by `widgetRenderingMode` (§1.1): `.fullColor` uses the
//  tool's color on the ring, icon and name, with the value in the primary
//  text; `.accented` marks only the ring and the icon `.widgetAccentable()`
//  and never sets a color; `.vibrant` has no color of its own, only opacity.
//

import SwiftUI

#if canImport(WidgetKit) && (os(iOS) || os(watchOS))
import WidgetKit

// MARK: - Building blocks

/// What the glyph and the circular gauge show.
nonisolated enum StComplicationProgress: Sendable {
    case none
    /// 0…1.
    case value(Double)
    /// Counts down by itself, without reloads (§2.3).
    case countdown(ClosedRange<Date>)
}

/// Icon of a complication: an SF Symbol, or a device outline.
nonisolated enum StComplicationIcon: Sendable {
    case symbol(String)
    case device(StDeviceBattery.Kind)

    /// For the inline family, which only takes an SF Symbol.
    var symbolName: String {
        switch self {
        case .symbol(let name): name
        case .device(let kind): kind.symbolName
        }
    }
}

/// One complication in the three accessory families.
struct StComplication: View {
    /// The tool's name ("Timer", "Monitor", "Dispositivos"), never the app's.
    let name: String
    let tone: Color
    let icon: StComplicationIcon
    let progress: StComplicationProgress
    /// Rectangular value ("4:12", "CPU 37%", "82 · 64 · 41").
    let value: Text
    /// Circular and inline value, when shorter than `value`.
    var shortValue: Text? = nil
    /// The value's own color in `.fullColor` (Coral for a low battery).
    var valueTone: Color? = nil
    /// Rectangular values to try, in order, when `value` doesn't fit (v0.13 §7).
    var compactValues: [Text] = []

    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode

    private var isFullColor: Bool { renderingMode == .fullColor }

    /// Ring, icon and name: the tool's color only in `.fullColor`.
    private var accent: Color { isFullColor ? tone : .primary }

    var body: some View {
        #if os(watchOS)
        // v0.13 §6.1: no opaque fill of its own on the watch. Leaving the
        // background out made watchOS show "Please adopt containerBackground
        // API", so it declares the system's translucent fill instead, like
        // the mirrored iPhone cards.
        content
            .containerBackground(.fill.tertiary, for: .widget)
        #else
        content
            .containerBackground(for: .widget) { Color.clear }
        #endif
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        default: inline
        }
    }

    // MARK: Rectangular

    private var rectangular: some View {
        HStack(spacing: 8) {
            glyph
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 0) {
                Text(name)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(accent)
                    .opacity(isFullColor ? 1 : 0.7)
                    .lineLimit(1)
                ViewThatFits(in: .horizontal) {
                    rectangularValue(value)
                    ForEach(compactValues.indices, id: \.self) { index in
                        rectangularValue(compactValues[index])
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private func rectangularValue(_ text: Text) -> some View {
        text
            .font(.system(size: 17, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(isFullColor ? (valueTone ?? .primary) : .primary)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    /// 44 pt: a ring with the icon inside, or the icon on the background.
    @ViewBuilder
    private var glyph: some View {
        ZStack {
            switch progress {
            case .none:
                AccessoryWidgetBackground()
            case .value(let fraction):
                Circle()
                    .stroke(accent.opacity(0.25), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: min(max(fraction, 0), 1))
                    .stroke(accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .widgetAccentable()
            case .countdown(let interval):
                ProgressView(timerInterval: interval, countsDown: true) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .progressViewStyle(.circular)
                .tint(accent)
                .widgetAccentable()
            }
            iconView(size: 17)
                .widgetAccentable()
        }
        .padding(2)
    }

    // MARK: Circular

    @ViewBuilder
    private var circular: some View {
        switch progress {
        case .value(let fraction):
            Gauge(value: min(max(fraction, 0), 1)) {
                iconView(size: 12)
            } currentValueLabel: {
                circularLabel
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(accent)
            .widgetAccentable()
        case .countdown(let interval):
            ZStack {
                AccessoryWidgetBackground()
                ProgressView(timerInterval: interval, countsDown: true) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .progressViewStyle(.circular)
                .tint(accent)
                .widgetAccentable()
                .padding(3)
                circularLabel
                    .padding(.horizontal, 7)
            }
        case .none:
            ZStack {
                AccessoryWidgetBackground()
                circularLabel
                    .padding(.horizontal, 7)
            }
        }
    }

    /// Icon above, short value below.
    private var circularLabel: some View {
        VStack(spacing: 0) {
            iconView(size: 11)
                .widgetAccentable()
            (shortValue ?? value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(isFullColor ? (valueTone ?? .primary) : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Inline

    private var inline: some View {
        ViewThatFits {
            Label {
                Text("\(name) · \(shortValue ?? value)")
            } icon: {
                Image(systemName: icon.symbolName)
            }
            Label {
                shortValue ?? value
            } icon: {
                Image(systemName: icon.symbolName)
            }
        }
    }

    // MARK: Icon

    @ViewBuilder
    private func iconView(size: CGFloat) -> some View {
        switch icon {
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(accent)
        case .device(let kind):
            StDeviceIcon(kind: kind, size: size + 2, color: accent)
        }
    }
}

// MARK: - Timer

/// Timer: the ring counts down by itself while running (§2.3).
struct StTimerComplication: View {
    let snapshot: StTimerSnapshot
    let date: Date

    private var phase: StTimerSnapshot.Phase { snapshot.phase(at: date) }

    private var total: TimeInterval {
        max(snapshot.total ?? snapshot.lastDuration, 1)
    }

    private var remaining: TimeInterval {
        phase == .idle ? snapshot.lastDuration : snapshot.remaining(at: date)
    }

    /// Ends at `fireDate` and lasts `total`, so the ring starts at the
    /// remaining fraction.
    private var interval: ClosedRange<Date>? {
        guard phase == .running, let fireDate = snapshot.fireDate else { return nil }
        return min(fireDate.addingTimeInterval(-total), date)...fireDate
    }

    private var progress: StComplicationProgress {
        if let interval { return .countdown(interval) }
        switch phase {
        case .idle: return .value(1)
        case .alerting: return .value(0)
        case .running, .paused: return .value(remaining / total)
        }
    }

    private var clock: Text {
        if let interval {
            return Text(timerInterval: date...interval.upperBound, countsDown: true)
        }
        return Text(StTimerSnapshot.format(remaining))
    }

    private var value: Text {
        switch phase {
        case .alerting: Text("Encerrado!")
        case .idle: Text("\(clock) definido")
        case .paused: Text("\(clock) pausado")
        case .running: clock
        }
    }

    var body: some View {
        StComplication(
            name: "Timer",
            tone: StTool.timer.tone,
            icon: .symbol(StTool.timer.systemImage),
            progress: progress,
            value: value,
            shortValue: phase == .alerting ? Text("Fim") : clock
        )
    }
}

// MARK: - Monitor

/// Monitor: the chosen (or pinned) metric's ring and "CPU 37%".
struct StMonitorComplication: View {
    let metric: StWidgetMetric
    let metrics: StMetricsSnapshot

    var body: some View {
        let level = metrics.value(metric)
        let percent = level.map { "\(Int(($0 * 100).rounded()))%" } ?? "—"
        let isLow = metric == .battery && metrics.isBatteryLow
        StComplication(
            name: "Monitor",
            tone: StTool.monitor.tone,
            icon: .symbol(metric.systemImage),
            progress: .value(level ?? 1),
            value: Text("\(metric.label) \(percent)"),
            shortValue: Text(percent),
            valueTone: isLow ? StTool.voice.tone : nil
        )
    }
}

// MARK: - Dispositivos

/// Dispositivos: the percents in the widget's order ("82 · 64 · 41"); the
/// glyph shows the device with the lowest charge, in its own color (Coral
/// when low). The circular shows the first device (v0.12.3 §3).
struct StDevicesComplication: View {
    /// Already in the widget's order, at most three.
    let devices: [StDeviceBattery]
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode

    private var lowest: StDeviceBattery? {
        devices.filter { $0.level != nil }.min { ($0.level ?? 1) < ($1.level ?? 1) } ?? devices.first
    }

    var body: some View {
        let shown = family == .accessoryRectangular ? lowest : devices.first
        if let shown {
            StComplication(
                name: "Dispositivos",
                tone: shown.levelRGB.color,
                icon: .device(shown.kind),
                progress: .value(shown.ringFraction),
                // v0.13 §7: each device's icon by its percent, in the
                // ring's color only in full color.
                value: StDeviceBattery.percentsLabel(devices, colored: renderingMode == .fullColor),
                shortValue: Text(family == .accessoryInline ? "\(shown.shortName) \(shown.percentText)" : shown.percentText),
                valueTone: shown.isLow ? shown.levelRGB.color : nil,
                compactValues: StDeviceBattery.percentsFallbacks(devices, colored: renderingMode == .fullColor)
            )
        } else {
            StComplication(
                name: "Dispositivos",
                tone: StTool.monitor.tone,
                icon: .symbol("battery.75percent"),
                progress: .none,
                value: Text("Sem dispositivos"),
                shortValue: Text("—")
            )
        }
    }
}
#endif

/// Short device names for the widgets: "iPhone", "Watch", "Mac".
extension StDeviceBattery {
    var shortName: String {
        switch kind {
        case .iphone: name
        case .watch: "Watch"
        case .mac: "Mac"
        }
    }
}
