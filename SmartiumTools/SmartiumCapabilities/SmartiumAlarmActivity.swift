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
            SmartiumTimerBannerView(state: context.state, tool: tool)
                .activityBackgroundTint(Color.black.opacity(0.9))
                .activitySystemActionForegroundColor(tool.tone)
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
                Text(SmartiumTimerStatus.format(paused.totalCountdownDuration - paused.previouslyElapsedDuration))
            default:
                Text("00:00")
            }
        }
        .monospacedDigit()
        .multilineTextAlignment(.trailing)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
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

    static func format(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let remaining = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, remaining)
            : String(format: "%02d:%02d", minutes, remaining)
    }
}

private struct SmartiumTimerBannerView: View {
    let state: AlarmPresentationState
    let tool: StTool

    var body: some View {
        HStack(spacing: 14) {
            SmartiumIslandIcon(tool: tool, size: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text("Timer")
                    .font(StFont.body(12, .semibold))
                    .foregroundStyle(tool.tone)
                Text(SmartiumTimerStatus.text(for: state))
                    .font(StFont.body(15, .bold))
                    .foregroundStyle(.white)
            }

            Spacer()

            SmartiumTimerCountdownText(state: state)
                .font(StFont.bigNumber(44))
                .foregroundStyle(tool.tone)
                .frame(maxWidth: 140, alignment: .trailing)
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
    }
}
#endif
