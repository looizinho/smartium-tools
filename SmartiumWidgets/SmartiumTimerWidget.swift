//
//  SmartiumTimerWidget.swift
//  SmartiumWidgets
//
//  Timer widgets. v0.12 §2: the Orb's layout and system theme. Medium: the
//  ring with the clock on the plate, "4:12 restantes", the end message and
//  time, Pausar / Iniciar and the round Zerar. Small: the ring with the
//  clock and a play / pause button. §4: Lock Screen (circular, rectangular,
//  inline), counting on their own with `timerInterval`; since v0.12.1 they
//  are `StTimerComplication`, shared with the watch.
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

    /// The app reloads on every change. While counting, entries move the
    /// ring (about 60 steps, at least 15 s apart; the clock counts by itself)
    /// up to the end.
    ///
    /// v0.12.1 §3: a safety net in case a reload gets lost. The timeline asks
    /// again at the end while counting, and every 30 min otherwise, so a
    /// missed reload heals by itself instead of freezing the widget.
    func getTimeline(in context: Context, completion: @escaping (Timeline<SmartiumTimerEntry>) -> Void) {
        let snapshot = StLiveSurfaces.timer
        let now = Date.now
        var entries = [SmartiumTimerEntry(date: now, snapshot: snapshot)]
        var refresh = now.addingTimeInterval(30 * 60)
        if snapshot.phase(at: now) == .running, let fireDate = snapshot.fireDate {
            refresh = fireDate
            let step = max(15, fireDate.timeIntervalSince(now) / 60)
            var date = now.addingTimeInterval(step)
            while date < fireDate {
                entries.append(SmartiumTimerEntry(date: date, snapshot: snapshot))
                date = date.addingTimeInterval(step)
            }
            entries.append(SmartiumTimerEntry(date: fireDate, snapshot: snapshot))
        }
        completion(Timeline(entries: entries, policy: .after(refresh)))
    }
}

struct SmartiumTimerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: StLiveSurfaces.timerWidgetKind, provider: SmartiumTimerProvider()) { entry in
            SmartiumTimerWidgetView(entry: entry)
                .widgetURL(StTool.timer.deepLink)
        }
        .configurationDisplayName("Timer")
        .description("Tempo restante do timer, com pausar e zerar.")
        .supportedFamilies([
            .systemSmall, .systemMedium,
            .accessoryCircular, .accessoryRectangular, .accessoryInline,
        ])
    }
}

struct SmartiumTimerWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SmartiumTimerEntry

    private let tool = StTool.timer
    private var snapshot: StTimerSnapshot { entry.snapshot }
    private var phase: StTimerSnapshot.Phase { snapshot.phase(at: entry.date) }

    var body: some View {
        switch family {
        case .accessoryCircular, .accessoryRectangular, .accessoryInline:
            StTimerComplication(snapshot: snapshot, date: entry.date)
        case .systemMedium:
            medium.stWidgetBackground(tool.tone)
        default:
            small.stWidgetBackground(tool.tone)
        }
    }

    // MARK: Layouts

    private var medium: some View {
        StWidgetMediumLayout(
            tone: tool.tone,
            systemImage: tool.systemImage,
            brand: "Timer",
            title: title,
            caption: Text(caption)
        ) {
            ring(lineWidth: 7, clockSize: hasHours ? 15 : 20)
        } actions: {
            Button(intent: ToggleTimerIntent(running: phase != .running)) {
                StWidgetCapsule(title: toggleTitle, systemImage: toggleSymbol, tone: tool.tone)
            }
            .buttonStyle(.plain)

            Button(intent: ResetTimerIntent()) {
                Image(systemName: "arrow.counterclockwise")
                    .font(StFont.body(11, .bold))
                    .foregroundStyle(StTool.voice.tone)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(StTool.voice.opacity(0.16)))
                    .overlay(Circle().strokeBorder(StTool.voice.opacity(0.35), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Zerar")
        }
    }

    private var small: some View {
        StWidgetSmallLayout(label: Text(smallLabel)) {
            Button(intent: ToggleTimerIntent(running: phase != .running)) {
                StWidgetRoundButton(systemImage: toggleSymbol, tone: tool.tone)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(toggleTitle)
        } element: {
            ring(lineWidth: 6, clockSize: hasHours ? 13 : 17)
        }
    }

    // MARK: Ring

    /// Seconds shown; when idle, the duration a start would use.
    private var shownSeconds: TimeInterval {
        phase == .idle ? snapshot.lastDuration : snapshot.remaining(at: entry.date)
    }

    private var hasHours: Bool { shownSeconds >= 3_600 }

    private var total: TimeInterval {
        max(snapshot.total ?? snapshot.lastDuration, 1)
    }

    private var fraction: Double {
        switch phase {
        case .idle: 1
        case .alerting: 0
        case .running, .paused: snapshot.remaining(at: entry.date) / total
        }
    }

    private func ring(lineWidth: CGFloat, clockSize: CGFloat) -> some View {
        StWidgetRing(fraction: fraction, color: tool.tone, lineWidth: lineWidth) {
            SmartiumTimerClock(snapshot: snapshot, date: entry.date, size: clockSize)
        }
    }

    // MARK: Texts

    private var title: Text {
        switch phase {
        case .running:
            if let fireDate = snapshot.fireDate {
                return Text("\(Text(timerInterval: entry.date...fireDate, countsDown: true)) restantes")
            }
            return Text("\(StTimerSnapshot.format(shownSeconds)) restantes")
        case .paused:
            return Text("\(StTimerSnapshot.format(shownSeconds)) restantes")
        case .idle:
            return Text("\(StTimerSnapshot.format(shownSeconds)) definido")
        case .alerting:
            return Text("Encerrado!")
        }
    }

    /// The end message and, while counting, the end time.
    private var caption: String {
        let message = snapshot.message.isEmpty ? LimitimerSettings.defaultEndMessage : snapshot.message
        switch phase {
        case .running:
            let end = (snapshot.fireDate ?? entry.date).formatted(date: .omitted, time: .shortened)
            return "\(message) · termina às \(end)"
        case .paused:
            return "\(message) · pausado"
        case .idle, .alerting:
            return message
        }
    }

    private var smallLabel: String {
        switch phase {
        case .running: "Restante"
        case .paused: "Pausado"
        case .idle: "Definido"
        case .alerting: "Encerrado!"
        }
    }

    private var toggleTitle: LocalizedStringKey {
        switch phase {
        case .running: "Pausar"
        case .paused: "Retomar"
        case .alerting: "Parar"
        case .idle: "Iniciar"
        }
    }

    private var toggleSymbol: String {
        switch phase {
        case .running: "pause.fill"
        case .alerting: "stop.fill"
        case .paused, .idle: "play.fill"
        }
    }
}

/// The clock inside the ring: counts by itself while running.
///
/// v0.12.2 §2: painted through a mask, like `StBigNumber`. Since the Xcode
/// 27.3 SDK a `Text` in Digital Dotted draws its digits black whatever its
/// `foregroundStyle`, which hid the clock on the dark widget. The mask only
/// uses the glyphs' alpha, so the theme color always shows, and the
/// `Text(timerInterval:)` inside it keeps counting on its own.
private struct SmartiumTimerClock: View {
    let snapshot: StTimerSnapshot
    let date: Date
    let size: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let phase = snapshot.phase(at: date)
        clockText(phase)
            .foregroundStyle(.clear)
            .overlay {
                StWidgetTheme(colorScheme).primary
                    .opacity(phase == .idle ? 0.55 : 1)
                    .mask { clockText(phase) }
            }
            .accessibilityElement(children: .combine)
    }

    private func clockText(_ phase: StTimerSnapshot.Phase) -> some View {
        Group {
            if phase == .running, let fireDate = snapshot.fireDate {
                Text(timerInterval: date...fireDate, countsDown: true)
            } else {
                Text(StTimerSnapshot.format(phase == .idle ? snapshot.lastDuration : snapshot.remaining(at: date)))
            }
        }
        .font(StFont.bigNumber(size))
        .monospacedDigit()
        .multilineTextAlignment(.center)
        .lineLimit(1)
        .minimumScaleFactor(0.5)
    }
}

#endif
