//
//  SmartiumAlarmActivity.swift
//  SmartiumTools
//
//  AlarmKit metadata shared by the app (which schedules timers) and the
//  widget extension (which renders the timer's Live Activity / Dynamic Island).
//

import SwiftUI

#if canImport(AlarmKit) && os(iOS)
import ActivityKit
import AppIntents
import AlarmKit
import WidgetKit

/// Metadata for SmartiumTools timers. `toolRaw` names the tool that owns the
/// activity so the island uses that tool's color (handoff v0.2).
nonisolated struct SmartiumAlarmMetadata: AlarmMetadata {
    var toolRaw: String?

    init(tool: StTool = .timer) {
        toolRaw = tool.rawValue
    }

    var tool: StTool {
        toolRaw.flatMap(StTool.init(rawValue:)) ?? .timer
    }
}

/// Lock Screen and Dynamic Island for AlarmKit timers, in the owning tool's color.
struct SmartiumTimerLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<SmartiumAlarmMetadata>.self) { context in
            let tool = context.attributes.metadata?.tool ?? .timer
            // v0.13 §6.3: the system material, in the Lock Screen's dark scheme.
            SmartiumTimerBannerView(state: context.state, tool: tool)
                .activitySystemActionForegroundColor(tool.tone)
                // v0.8: always open on the owning tool's tab.
                .widgetURL(tool.deepLink)
        } dynamicIsland: { context in
            let tool = context.attributes.metadata?.tool ?? .timer
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    SmartiumIslandIcon(tool: tool, size: 36)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    SmartiumTimerCountdownText(state: context.state)
                        .font(StFont.bigNumber(44))
                        .foregroundStyle(tool.tone)
                        .frame(maxWidth: 110, alignment: .trailing)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(StTool.timer.tone)
                            .frame(width: 7, height: 7)
                        Text(SmartiumTimerStatus.text(for: context.state))
                            .font(StFont.body(12, .semibold))
                            .foregroundStyle(.white.opacity(0.75))
                        Spacer()
                        SmartiumTimerActivityButtons(state: context.state, tool: tool, size: 36)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6)
                }
            } compactLeading: {
                SmartiumIslandIcon(tool: tool, size: 22)
            } compactTrailing: {
                SmartiumTimerCountdownText(state: context.state)
                    .font(StFont.bigNumber(15))
                    .foregroundStyle(tool.tone)
                    .frame(maxWidth: 52)
            } minimal: {
                SmartiumIslandIcon(tool: tool, size: 22)
            }
            .keylineTint(tool.tone)
            .widgetURL(tool.deepLink)
        }
    }
}

/// Tool icon on a 22% tint circle (compact leading / minimal).
struct SmartiumIslandIcon: View {
    let tool: StTool
    var size: CGFloat = 22

    var body: some View {
        Image(systemName: tool.systemImage)
            .font(StFont.body(size * 0.64, .semibold))
            .foregroundStyle(tool.tone)
            .frame(width: size, height: size)
            .background(Circle().fill(tool.opacity(0.22)))
    }
}

/// Live countdown while running, the frozen remaining time while paused.
/// Callers set `StFont.bigNumber` in the tool color (v0.4): the system keeps
/// drawing the countdown, so it stays live without app updates.
private struct SmartiumTimerCountdownText: View {
    let state: AlarmPresentationState

    var body: some View {
        Group {
            switch state.mode {
            case .countdown(let countdown):
                Text(timerInterval: Date.now...max(countdown.fireDate, .now), countsDown: true)
            case .paused(let paused):
                Text(StTimerSnapshot.format(paused.totalCountdownDuration - paused.previouslyElapsedDuration))
            default:
                Text(StTimerSnapshot.format(0))
            }
        }
        .monospacedDigit()
        .multilineTextAlignment(.trailing)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
}

/// Pausar/Retomar and Zerar in the Live Activity (v0.5; Zerar since v0.12.2). The intents are
/// `LiveActivityIntent`s, so they run in the app process without opening it
/// and keep the Timer widgets and control in step. A ringing timer only gets
/// the stop button.
private struct SmartiumTimerActivityButtons: View {
    let state: AlarmPresentationState
    let tool: StTool
    let size: CGFloat

    var body: some View {
        HStack(spacing: 8) {
            switch state.mode {
            case .countdown:
                button(ToggleTimerIntent(running: false), symbol: "pause.fill", label: "Pausar")
                resetButton
            case .paused:
                button(ToggleTimerIntent(running: true), symbol: "play.fill", label: "Retomar")
                resetButton
            default:
                button(ToggleTimerIntent(running: false), symbol: "stop.fill", label: "Parar")
            }
        }
    }

    private func button(_ intent: ToggleTimerIntent, symbol: String, label: String) -> some View {
        Button(intent: intent) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.36, weight: .bold))
                .foregroundStyle(Color.stInk900)
                .frame(width: size, height: size)
                .background(Circle().fill(tool.tone))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var resetButton: some View {
        Button(intent: ResetTimerIntent()) {
            Image(systemName: "arrow.counterclockwise")
                .font(.system(size: size * 0.36, weight: .bold))
                .foregroundStyle(StTool.voice.tone)
                .frame(width: size, height: size)
                .background(Circle().fill(StTool.voice.opacity(0.16)))
                .overlay(Circle().strokeBorder(StTool.voice.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Zerar")
    }
}

private nonisolated enum SmartiumTimerStatus {
    static func text(for state: AlarmPresentationState) -> String {
        switch state.mode {
        case .countdown: "Em andamento"
        case .paused: "Pausado"
        default: "Encerrado!"
        }
    }
}

/// Lock Screen and banner card. v0.13 §6.3 (replaces v0.12.2 §3): the
/// Lock Screen is a dark context, so text and rings use the dark scheme in
/// both system themes, over the system's default material
/// instead of black at 90%. `activityBackgroundTint(nil)` drew opaque black
/// on the device, so the card uses the handoff's fallback: the tool color
/// at 18%, translucent over the wallpaper.
private struct SmartiumTimerBannerView: View {
    let state: AlarmPresentationState
    let tool: StTool

    var body: some View {
        let theme = StWidgetTheme(.dark)
        HStack(spacing: 14) {
            SmartiumIslandIcon(tool: tool, size: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text("Timer")
                    .font(StFont.body(12, .semibold))
                    .foregroundStyle(tool.tone)
                Text(SmartiumTimerStatus.text(for: state))
                    .font(StFont.body(15, .bold))
                    .foregroundStyle(theme.primary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
                SmartiumTimerCountdownText(state: state)
                    .font(StFont.bigNumber(44))
                    .foregroundStyle(tool.tone)
                    .frame(maxWidth: 140, alignment: .trailing)
                SmartiumTimerActivityButtons(state: state, tool: tool, size: 40)
            }
        }
        .padding(14)
        .background(
            RadialGradient(
                colors: [tool.opacity(0.24), .clear],
                center: .topTrailing,
                startRadius: 8,
                endRadius: 180
            )
        )
        .environment(\.colorScheme, .dark)
        .activityBackgroundTint(tool.opacity(0.18))
    }
}
#endif
