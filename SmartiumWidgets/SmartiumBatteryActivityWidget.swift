//
//  SmartiumBatteryActivityWidget.swift
//  SmartiumWidgets
//
//  The devices' batteries in the Dynamic Island and on the Lock Screen
//  (handoff v0.12 §3.3). Compact: the icon of the device that changed and
//  "82% · 64% · 41%". Minimal: the icon of the device with the lowest
//  charge. Expanded and Lock Screen: the three concentric rings (92 pt) and
//  one row per device, under a `DISPOSITIVOS` header in Íris with the last
//  update's time. Low battery in Coral. Opens the Monitor.
//

import AppIntents
import SwiftUI
import WidgetKit

#if canImport(ActivityKit) && os(iOS)
import ActivityKit

struct SmartiumBatteryActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: StBatteryActivityAttributes.self) { context in
            SmartiumBatteryLockScreenView(state: context.state)
                .activitySystemActionForegroundColor(StTool.orb.tone)
                .widgetURL(StTool.monitor.deepLink)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    SmartiumBatteryHeader()
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    SmartiumBatteryTime(date: state.updatedAt)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    SmartiumBatteryBody(state: state, primary: .white)
                        .padding(.top, 4)
                }
            } compactLeading: {
                if let device = state.changed {
                    StDeviceIcon(kind: device.kind, size: 16, color: device.rgb.color)
                }
            } compactTrailing: {
                Text(state.ringDevices.map(\.percentText).joined(separator: " · "))
                    .font(StFont.body(12, .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } minimal: {
                if let device = state.lowest {
                    StDeviceIcon(kind: device.kind, size: 16, color: device.levelRGB.color)
                }
            }
            .keylineTint(StTool.orb.tone)
            .widgetURL(StTool.monitor.deepLink)
        }
    }
}

/// `DISPOSITIVOS` in Íris.
private struct SmartiumBatteryHeader: View {
    var body: some View {
        Text("DISPOSITIVOS")
            .font(StFont.body(11, .heavy))
            .tracking(1.2)
            .foregroundStyle(StTool.orb.tone)
    }
}

/// The last update's time, on the right of the header.
private struct SmartiumBatteryTime: View {
    let date: Date

    var body: some View {
        Text(date, style: .time)
            .font(StFont.body(11, .semibold))
            .monospacedDigit()
            .foregroundStyle(.secondary)
    }
}

/// Rings on the left, one row per device on the right.
private struct SmartiumBatteryBody: View {
    let state: StBatteryActivityAttributes.ContentState
    let primary: Color

    var body: some View {
        HStack(spacing: 16) {
            StDeviceRingsMark(devices: state.devices)
                .frame(width: 92, height: 92)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(state.ringDevices) { device in
                    row(device)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func row(_ device: StDeviceBattery) -> some View {
        HStack(spacing: 6) {
            StDeviceIcon(kind: device.kind, size: 16, color: device.rgb.color)
            Text(device.name)
                .font(StFont.body(13, .semibold))
                .foregroundStyle(primary)
                .lineLimit(1)
            if device.isCharging {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(StTool.timer.tone)
            }
            Spacer(minLength: 4)
            Text(device.percentText)
                .font(StFont.body(15, .heavy))
                .monospacedDigit()
                .foregroundStyle(device.isLow ? device.levelRGB.color : primary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(device.spoken(isThisDevice: false))
    }
}

/// Lock Screen card, in the system theme like the Orb's banner.
private struct SmartiumBatteryLockScreenView: View {
    let state: StBatteryActivityAttributes.ContentState
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = StWidgetTheme(colorScheme)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SmartiumBatteryHeader()
                Spacer()
                SmartiumBatteryTime(date: state.updatedAt)
            }
            SmartiumBatteryBody(state: state, primary: theme.primary)
        }
        .padding(14)
        .background {
            ZStack {
                if theme.isDark {
                    Color.black.opacity(0.90)
                } else {
                    StWidgetTheme.paper.opacity(0.94)
                }
                RadialGradient(
                    colors: [StTool.orb.opacity(theme.isDark ? 0.24 : 0.14), Color.clear],
                    center: .topTrailing,
                    startRadius: 8,
                    endRadius: 180
                )
            }
        }
    }
}
#endif
