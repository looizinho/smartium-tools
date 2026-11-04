//
//  SmartiumWidgetViews.swift
//  SmartiumTools
//
//  Ready-to-use WidgetKit views, TimelineProvider, and Dynamic Island configurations
//  for SmartiumTools Home Screen Widgets and Live Activities.
//

import AppIntents
import SwiftUI
#if canImport(WidgetKit)
import WidgetKit

// MARK: - Home Screen Widget Timeline

nonisolated public struct SmartiumOrbTimelineEntry: TimelineEntry, Sendable {
    public let date: Date
    public let sharedState: ToolSharedState

    public init(date: Date = .now, sharedState: ToolSharedState = .load()) {
        self.date = date
        self.sharedState = sharedState
    }
}

nonisolated public struct SmartiumOrbTimelineProvider: TimelineProvider {
    public init() {}

    public func placeholder(in context: Context) -> SmartiumOrbTimelineEntry {
        SmartiumOrbTimelineEntry(date: .now, sharedState: ToolSharedState())
    }

    public func getSnapshot(in context: Context, completion: @escaping (SmartiumOrbTimelineEntry) -> Void) {
        completion(SmartiumOrbTimelineEntry(date: .now, sharedState: ToolSharedState.load()))
    }

    public func getTimeline(in context: Context, completion: @escaping (Timeline<SmartiumOrbTimelineEntry>) -> Void) {
        let currentState = ToolSharedState.load()
        let now = Date.now
        var entries: [SmartiumOrbTimelineEntry] = []

        // Generate 12 deterministic snapshots spaced 5 minutes apart so the orb
        // geometry subtly evolves on the Home Screen without draining battery.
        for offset in 0..<12 {
            let entryDate = Calendar.current.date(byAdding: .minute, value: offset * 5, to: now) ?? now
            entries.append(SmartiumOrbTimelineEntry(date: entryDate, sharedState: currentState))
        }

        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

// MARK: - Home Screen Widget Views (.systemSmall & .systemMedium)

public struct SmartiumOrbWidgetEntryView: View {
    public let entry: SmartiumOrbTimelineEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme

    public init(entry: SmartiumOrbTimelineEntry) {
        self.entry = entry
    }

    /// Widgets take the color of their tool's screen.
    /// The only widget today is the Orb's, so it is Íris.
    private let tone = StTool.orb.tone

    private var isDark: Bool {
        colorScheme == .dark
    }

    private var primaryTextColor: Color {
        isDark ? .white : Color(red: 0.10, green: 0.09, blue: 0.14)
    }

    private var secondaryTextColor: Color {
        isDark ? .white.opacity(0.70) : Color(red: 0.10, green: 0.09, blue: 0.14).opacity(0.62)
    }

    /// Deterministic instant derived from the entry timestamp and preset speed.
    private var frozenInstant: Double {
        let base = (entry.sharedState.updatedAt.timeIntervalSinceReferenceDate
            + entry.date.timeIntervalSince(entry.sharedState.updatedAt))
            .truncatingRemainder(dividingBy: 3600)
        return base * resolvePreset(entry.sharedState.orbState, .px64).speed
    }

    public var body: some View {
        Group {
            switch family {
            case .systemMedium:
                mediumLayout
            default:
                smallLayout
            }
        }
        .containerBackground(for: .widget) {
            ZStack {
                if isDark {
                    Color.black.opacity(0.92)
                } else {
                    Color(red: 0.98, green: 0.97, blue: 1.00)
                }
                RadialGradient(
                    colors: [
                        tone.opacity(isDark ? 0.28 : 0.16),
                        Color.clear
                    ],
                    center: .topTrailing,
                    startRadius: 8,
                    endRadius: 160
                )
            }
        }
    }

    private var smallLayout: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Smartium")
                    .font(StFont.body(11, .bold))
                    .foregroundStyle(secondaryTextColor)
                Spacer()
                Button(intent: CycleOrbStateIntent()) {
                    Image(systemName: "arrow.trianglehead.2.clockwise")
                        .font(StFont.body(11, .bold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(tone))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Próximo Estado")
            }

            // Not a button: tapping the orb opens the app (only the explicit
            // button cycles the state).
            ThinkingOrb(
                state: entry.sharedState.orbState,
                size: .px64,
                theme: .auto,
                displaySize: 68
            )
            .orbFrozenTime(frozenInstant)

            Text(entry.sharedState.orbState.label)
                .font(StFont.body(12, .semibold))
                .foregroundStyle(primaryTextColor)
                .lineLimit(1)
        }
    }

    private var mediumLayout: some View {
        HStack(spacing: 16) {
            ThinkingOrb(
                state: entry.sharedState.orbState,
                size: .px64,
                theme: .auto,
                displaySize: 84
            )
            .orbFrozenTime(frozenInstant)
            .padding(6)
            .background(
                Circle()
                    .fill(isDark ? .white.opacity(0.05) : tone.opacity(0.07))
            )

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(tone)
                    Text(entry.sharedState.activeToolName)
                        .font(StFont.body(12, .semibold))
                        .foregroundStyle(tone)
                }

                Text(entry.sharedState.orbState.label)
                    .font(StFont.body(17, .semibold))
                    .foregroundStyle(primaryTextColor)

                if let progress = entry.sharedState.stepProgress {
                    ProgressView(value: progress)
                        .tint(tone)
                } else {
                    Text("Toque no botão para alternar o estado.")
                        .font(StFont.body(11))
                        .foregroundStyle(secondaryTextColor)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                Button(intent: CycleOrbStateIntent()) {
                    Label("Próximo Estado", systemImage: "arrow.trianglehead.2.clockwise")
                        .font(StFont.body(11, .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(tone.opacity(isDark ? 0.85 : 0.90)))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }
}

/// Home Screen Widget definition ready to be added to the Widget Extension's `WidgetBundle`.
public struct SmartiumOrbWidget: Widget {
    public let kind: String = "SmartiumOrbWidget"

    public init() {}

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SmartiumOrbTimelineProvider()) { entry in
            SmartiumOrbWidgetEntryView(entry: entry)
                .tint(StTool.orb.tone)
                .widgetURL(StTool.orb.deepLink)
        }
        .configurationDisplayName("Smartium Orb")
        .description("Exibe e controla o estado atual das ferramentas do SmartiumTools.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Dynamic Island & Lock Screen Views (ActivityKit)

#if canImport(ActivityKit) && os(iOS)
import ActivityKit

/// Lock Screen / Notification Banner presentation for an active SmartiumTools session.
public struct SmartiumLockScreenBannerView: View {
    public let toolTitle: String
    public let state: SmartiumActivityAttributes.ContentState
    public let isStale: Bool
    @Environment(\.colorScheme) private var colorScheme

    public init(toolTitle: String, state: SmartiumActivityAttributes.ContentState, isStale: Bool = false) {
        self.toolTitle = toolTitle
        self.state = state
        self.isStale = isStale
    }

    /// Live Activity color comes from the owning tool (v0.2).
    private var tone: Color { state.tool.tone }

    private var isDark: Bool {
        colorScheme == .dark
    }

    private var primaryTextColor: Color {
        isDark ? .white : Color(red: 0.10, green: 0.09, blue: 0.14)
    }

    private var secondaryTextColor: Color {
        isDark ? .white.opacity(0.80) : Color(red: 0.10, green: 0.09, blue: 0.14).opacity(0.68)
    }

    private var frozenInstant: Double {
        let base = state.updatedAt.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600)
        return base * resolvePreset(state.orbState, .px64).speed
    }

    public var body: some View {
        HStack(spacing: 14) {
            ThinkingOrb(
                state: state.orbState,
                size: .px64,
                theme: .auto,
                displaySize: 52
            )
            .orbFrozenTime(frozenInstant)
            .colorMultiply(state.animationEndsAt != nil && !isStale ? tone : .white)
            .transaction { $0.animation = nil }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(StFont.body(12))
                        .foregroundStyle(tone)
                    Text(toolTitle)
                        .font(StFont.body(12, .semibold))
                        .foregroundStyle(secondaryTextColor)
                }

                Text(state.statusText)
                    .font(StFont.body(15, .bold))
                    .foregroundStyle(primaryTextColor)
                    .contentTransition(.numericText())

                if let progress = state.stepProgress {
                    ProgressView(value: progress)
                        .tint(tone)
                }
            }

            Spacer()

            Button(intent: CycleOrbStateIntent()) {
                Image(systemName: "arrow.trianglehead.2.clockwise")
                    .font(StFont.body(15, .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(tone))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background {
            ZStack {
                if isDark {
                    Color.black.opacity(0.90)
                } else {
                    Color(red: 0.98, green: 0.97, blue: 1.00).opacity(0.94)
                }
                RadialGradient(
                    colors: [
                        tone.opacity(isDark ? 0.24 : 0.14),
                        Color.clear
                    ],
                    center: .topTrailing,
                    startRadius: 8,
                    endRadius: 180
                )
            }
        }
    }
}

/// Tool icon on a 22×22 circle at 22% of the tool color.
struct SmartiumLiveActivityIcon: View {
    let tool: StTool

    var body: some View {
        Image(systemName: tool.systemImage)
            .font(StFont.body(14, .semibold))
            .foregroundStyle(tool.tone)
            .frame(width: 22, height: 22)
            .background(Circle().fill(tool.opacity(0.22)))
    }
}

/// Complete Live Activity & Dynamic Island Widget configuration ready for `WidgetBundle`.
public struct SmartiumLiveActivityWidget: Widget {
    public init() {}

    public var body: some WidgetConfiguration {
        ActivityConfiguration(for: SmartiumActivityAttributes.self) { context in
            let tone = context.state.tool.tone
            SmartiumLockScreenBannerView(
                toolTitle: context.attributes.toolTitle,
                state: context.state,
                isStale: context.isStale
            )
            .activitySystemActionForegroundColor(tone)
            // v0.8: always open on the owning tool's tab.
            .widgetURL(context.state.tool.deepLink)
        } dynamicIsland: { context in
            let tool = context.state.tool
            let tone = tool.tone
            let rawInstant = context.state.updatedAt.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600)
            let orbState = context.state.orbState
            let expandedInstant = rawInstant * resolvePreset(orbState, .px64).speed

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        ThinkingOrb(
                            state: orbState,
                            size: .px64,
                            theme: .dark,
                            displaySize: 44
                        )
                        .orbFrozenTime(expandedInstant)
                        .colorMultiply(context.state.animationEndsAt != nil && !context.isStale ? tone : .white)
                        .transaction { $0.animation = nil }
                    }
                    .padding(.leading, 4)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(context.attributes.toolTitle)
                            .font(StFont.body(11, .semibold))
                            .foregroundStyle(tone)
                        Text(context.state.statusText)
                            .font(StFont.body(12, .bold))
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())
                    }
                    .padding(.trailing, 4)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 10) {
                        Button(intent: CycleOrbStateIntent()) {
                            Label("Próximo Estado", systemImage: "sparkles")
                                .font(StFont.body(12, .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(tone.opacity(0.85)))
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)

                        Button(intent: StopLiveActivityIntent()) {
                            Image(systemName: "xmark")
                                .font(StFont.body(12, .bold))
                                .padding(8)
                                .background(Circle().fill(.white.opacity(0.15)))
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 4)
                }
            } compactLeading: {
                // v0.2: tool icon (14pt) in the tool color on a 22% tint circle.
                SmartiumLiveActivityIcon(tool: tool)
            } compactTrailing: {
                Text(orbState.label)
                    .font(StFont.body(13, .semibold))
                    .monospacedDigit()
                    .foregroundStyle(tone)
                    .lineLimit(1)
                    .contentTransition(.numericText())
            } minimal: {
                SmartiumLiveActivityIcon(tool: tool)
            }
            .keylineTint(tone)
            .widgetURL(tool.deepLink)
        }
    }
}
#endif
#endif
