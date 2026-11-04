//
//  SmartiumTimerWidget.swift
//  SmartiumWidgets
//
//  Timer widgets (handoff v0.5). Small: the remaining time. Medium: the time
//  plus Pausar/Retomar and Reiniciar, with the same intents as the control.
//

import AppIntents
import SwiftUI
import WidgetKit

#if canImport(AlarmKit) && os(iOS)
struct SmartiumTimerEntry: TimelineEntry {
    let date: Date
    let snapshot: StTimerSnapshot
}

struct SmartiumTimerProvider: TimelineProvider {
    func placeholder(in context: Context) -> SmartiumTimerEntry {
        SmartiumTimerEntry(date: .now, snapshot: StTimerSnapshot())
    }

    func getSnapshot(in context: Context, completion: @escaping (SmartiumTimerEntry) -> Void) {
        completion(SmartiumTimerEntry(date: .now, snapshot: StLiveSurfaces.timer))
    }

    /// The app reloads on every change; the only scheduled entry is the end of the countdown.
    func getTimeline(in context: Context, completion: @escaping (Timeline<SmartiumTimerEntry>) -> Void) {
        let snapshot = StLiveSurfaces.timer
        var entries = [SmartiumTimerEntry(date: .now, snapshot: snapshot)]
        if snapshot.phase(at: .now) == .running, let fireDate = snapshot.fireDate {
            entries.append(SmartiumTimerEntry(date: fireDate, snapshot: snapshot))
        }
        completion(Timeline(entries: entries, policy: .never))
    }
}

struct SmartiumTimerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: StLiveSurfaces.timerWidgetKind, provider: SmartiumTimerProvider()) { entry in
            SmartiumTimerWidgetView(entry: entry)
                .widgetURL(StTool.timer.deepLink)
        }
        .configurationDisplayName("Timer")
        .description("Tempo restante do timer, com pausar e reiniciar.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct SmartiumTimerWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SmartiumTimerEntry

    private var phase: StTimerSnapshot.Phase { entry.snapshot.phase(at: entry.date) }

    var body: some View {
        Group {
            if family == .systemMedium {
                HStack(spacing: 10) {
                    clock(size: hasHours ? 40 : 52)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    toggleButton
                    resetButton
                }
            } else {
                clock(size: hasHours ? 30 : 44)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .containerBackground(for: .widget) {
            SmartiumWidgetBackground(
                stops: [
                    .init(color: StTool.timer.opacity(0.3), location: 0),
                    .init(color: StAccent.sky.color(opacity: 0.08), location: 0.6),
                    .init(color: .stInk800, location: 0.9),
                ],
                center: family == .systemMedium ? UnitPoint(x: 0.2, y: 0.1) : UnitPoint(x: 0.3, y: 0.15),
                stroke: StTool.timer.opacity(0.25)
            )
        }
    }

    /// Seconds the clock shows; when idle, the duration a start would use.
    private var shownSeconds: TimeInterval {
        phase == .idle ? entry.snapshot.lastDuration : entry.snapshot.remaining(at: entry.date)
    }

    private var hasHours: Bool { shownSeconds >= 3_600 }

    private func clock(size: CGFloat) -> some View {
        Group {
            if phase == .running, let fireDate = entry.snapshot.fireDate {
                Text(timerInterval: entry.date...fireDate, countsDown: true)
            } else {
                Text(StTimerSnapshot.format(shownSeconds))
            }
        }
        .font(StFont.bigNumber(size))
        .foregroundStyle(.white.opacity(phase == .idle ? 0.55 : 1))
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }

    private var toggleButton: some View {
        let isRunning = phase == .running
        return Button(intent: ToggleTimerIntent(running: !isRunning)) {
            Image(systemName: isRunning ? "pause.fill" : "play.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color.stInk900)
                .frame(width: 56, height: 56)
                .background(Circle().fill(StTool.timer.tone))
                .shadow(color: StTool.timer.opacity(0.35), radius: 9, y: 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isRunning ? "Pausar" : "Retomar")
    }

    private var resetButton: some View {
        Button(intent: ResetTimerIntent()) {
            Image(systemName: "arrow.counterclockwise")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(StTool.voice.tone)
                .frame(width: 56, height: 56)
                .background(Circle().fill(StTool.voice.opacity(0.16)))
                .overlay(Circle().strokeBorder(StTool.voice.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Reiniciar")
    }
}
#endif

/// Radial glow over Ink 800 with a 1pt tinted inner stroke (v0.5 widgets).
struct SmartiumWidgetBackground: View {
    let stops: [Gradient.Stop]
    let center: UnitPoint
    let stroke: Color

    var body: some View {
        ZStack {
            Color.stInk800
            EllipticalGradient(stops: stops, center: center, startRadiusFraction: 0, endRadiusFraction: 0.9)
            ContainerRelativeShape()
                .strokeBorder(stroke, lineWidth: 1)
        }
    }
}
