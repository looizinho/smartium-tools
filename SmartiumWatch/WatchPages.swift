//
//  WatchPages.swift
//  SmartiumWatch
//
//  The three hero circles (handoff v0.10 §2), at the iPhone hero's values
//  with only the size changed. Voz and Monitor dim when the iPhone is out of
//  reach; the Timer keeps counting locally from `fireDate`. With the screen
//  dimmed (Always On) halos go, rings and numbers drop to 60% and motion stops.
//  v0.10.1: label, number and caption sizes follow the diameter.
//

import SwiftUI

/// Text sizes inside the circle, as fractions of its diameter (v0.10.1).
private enum WatchType {
    static func label(_ diameter: CGFloat) -> CGFloat { (diameter * 0.068).rounded() }
    static func number(_ diameter: CGFloat) -> CGFloat { (diameter * 0.24).rounded() }
    /// `h:mm:ss` drops to 20% so it fits the ring.
    static func longNumber(_ diameter: CGFloat) -> CGFloat { (diameter * 0.2).rounded() }
    static func caption(_ diameter: CGFloat) -> CGFloat { (diameter * 0.072).rounded() }
}

// MARK: - Voz

struct WatchVoicePage: View {
    let store: StWatchStore
    let diameter: CGFloat

    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        // Re-checked every few seconds for the "Sem iPhone" state.
        TimelineView(.periodic(from: .now, by: 5)) { context in
            let voice = store.state.voice
            let isOffline = store.isDisconnected(at: context.date)
            let caption = voice.listening ? "\(voice.modeTitle) · ouvindo" : voice.modeTitle
            ZStack {
                Group {
                    if isLuminanceReduced {
                        bars(listening: false, caption: caption)
                            .frame(width: diameter, height: diameter)
                    } else {
                        StHalo(.voice, size: diameter) {
                            bars(listening: voice.listening && !isOffline, caption: caption)
                        }
                    }
                }
                .opacity((isOffline ? 0.5 : 1) * (isLuminanceReduced ? 0.6 : 1))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottom) {
                if isOffline { WatchOfflineBadge(since: store.receivedAt, now: context.date) }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                ["Voz", voice.modeTitle, voice.listening ? "ouvindo" : nil, offlineLabel(isOffline, context.date)]
                    .compactMap { $0 }
                    .joined(separator: ", ")
            )
        }
    }

    private func bars(listening: Bool, caption: String) -> some View {
        VStack(spacing: diameter * 0.04) {
            WatchVoiceBars(diameter: diameter, listening: listening)
            Text(caption)
                .font(StFont.body(WatchType.caption(diameter), .semibold))
                .foregroundStyle(Color.white.opacity(0.6))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private func offlineLabel(_ isOffline: Bool, _ now: Date) -> String? {
        isOffline ? "sem iPhone, atualizado \(WatchOfflineBadge.ago(store.receivedAt, now: now, spoken: true))" : nil
    }
}

/// Five bars: Coral, Coral, Âmbar, Coral, Coral. 4.5% wide with 3.5% gaps,
/// up to 26% tall. While listening each pulses from 0.55 to 1 at its own pace.
private struct WatchVoiceBars: View {
    let diameter: CGFloat
    let listening: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let heights: [CGFloat] = [0.22, 0.55, 1, 0.55, 0.22]
    private static let periods: [Double] = [0.9, 1.1, 0.8, 1.05, 0.95]

    var body: some View {
        let isMoving = listening && !reduceMotion
        TimelineView(.animation(paused: !isMoving)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: diameter * 0.035) {
                ForEach(0..<5, id: \.self) { index in
                    let scale = isMoving
                        ? 0.55 + 0.45 * (0.5 + 0.5 * sin(2 * .pi * time / Self.periods[index]))
                        : 1
                    Capsule()
                        .fill(index == 2 ? StTool.voice.secondary : StTool.voice.tone)
                        .frame(width: diameter * 0.045, height: diameter * 0.26 * Self.heights[index])
                        .scaleEffect(x: 1, y: scale)
                }
            }
            .frame(height: diameter * 0.26)
        }
    }
}

// MARK: - Timer

struct WatchTimerPage: View {
    let timer: StTimerSnapshot
    let diameter: CGFloat

    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    private static let mint = StTool.timer
    private static let sky = StAccent.sky

    var body: some View {
        // Counts locally from `fireDate`: no value per second from the iPhone.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let reading = Reading(timer, at: context.date)
            // Always On updates less than once a second: no frozen seconds.
            let coarse = context.cadence >= .minutes && reading.kind == .running
            ring(reading, coarse: coarse)
                .opacity(isLuminanceReduced ? 0.6 : 1)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(reading.spoken)
        }
    }

    private func ring(_ reading: Reading, coarse: Bool) -> some View {
        StDialRing(
            size: diameter,
            fraction: reading.fraction,
            ringColor: Self.mint.tone,
            trackColor: Self.mint.opacity(0.14),
            tickColor: Self.sky.color(opacity: 0.45),
            lineWidth: 5.5,
            tickRadius: 36,
            halo: isLuminanceReduced ? [.init(color: .clear, location: 0)] : [
                .init(color: Self.mint.opacity(0.22), location: 0),
                .init(color: Self.sky.color(opacity: 0.08), location: 0.5),
                .init(color: Self.mint.opacity(0), location: 0.7)
            ]
        ) {
            VStack(spacing: 2) {
                Text(reading.label)
                    .font(StFont.body(WatchType.label(diameter), .heavy))
                    .tracking(1.3)
                    .foregroundStyle(Self.sky.color)
                if coarse {
                    StBigNumber(String(reading.minutesLeft), unit: "min", size: WatchType.number(diameter))
                } else {
                    let clock = StTimerSnapshot.format(reading.seconds)
                    StBigNumber(
                        clock,
                        size: clock.count > 5 ? WatchType.longNumber(diameter) : WatchType.number(diameter)
                    )
                }
                Text(reading.caption)
                    .font(StFont.body(WatchType.caption(diameter)))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }

    /// What the ring shows at a given moment.
    private struct Reading {
        enum Kind { case ready, running, paused, ended }

        let kind: Kind
        let seconds: TimeInterval
        let fraction: Double

        init(_ timer: StTimerSnapshot, at date: Date) {
            let total = max(timer.total ?? timer.lastDuration, 1)
            switch timer.phase {
            case .running where (timer.fireDate ?? date) <= date, .alerting:
                kind = .ended
                seconds = 0
                fraction = 0
            case .running:
                kind = .running
                seconds = timer.remaining(at: date)
                fraction = seconds / total
            case .paused:
                kind = .paused
                seconds = timer.remaining(at: date)
                fraction = seconds / total
            case .idle:
                kind = .ready
                seconds = timer.lastDuration
                fraction = 1
            }
        }

        var minutesLeft: Int { Int((seconds / 60).rounded(.up)) }

        var label: String {
            switch kind {
            case .ready: "DEFINIDO"
            case .running, .paused: "RESTANTE"
            case .ended: "FIM"
            }
        }

        var caption: String {
            switch kind {
            case .ready: "Pronto"
            case .running: "Em andamento…"
            case .paused: "Pausado"
            case .ended: "Tempo esgotado"
            }
        }

        /// "Timer, 4 minutos e 12 segundos restantes, em andamento".
        var spoken: String {
            let total = max(0, Int(seconds.rounded(.up)))
            let hours = total / 3_600
            let minutes = (total % 3_600) / 60
            let rest = total % 60
            var parts: [String] = []
            if hours > 0 { parts.append("\(hours) \(hours == 1 ? "hora" : "horas")") }
            if minutes > 0 { parts.append("\(minutes) \(minutes == 1 ? "minuto" : "minutos")") }
            if rest > 0 || parts.isEmpty { parts.append("\(rest) \(rest == 1 ? "segundo" : "segundos")") }
            let time = parts.joined(separator: " e ")
            switch kind {
            case .ready: return "Timer, \(time), pronto"
            case .running: return "Timer, \(time) restantes, em andamento"
            case .paused: return "Timer, \(time) restantes, pausado"
            case .ended: return "Timer, tempo esgotado"
            }
        }
    }
}

// MARK: - Monitor

struct WatchMonitorPage: View {
    let store: StWatchStore
    let diameter: CGFloat

    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        TimelineView(.periodic(from: .now, by: 5)) { context in
            let monitor = store.state.monitor
            let metric = StWatchMetric(pinned: monitor.pinned)
            let value = monitor.snapshot.flatMap(metric.value(in:)) ?? 0
            let percent = Int((value * 100).rounded())
            let isOffline = store.isDisconnected(at: context.date)
            ring(metric: metric, value: value, percent: percent, detail: monitor.detail)
                .opacity((isOffline ? 0.5 : 1) * (isLuminanceReduced ? 0.6 : 1))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .bottom) {
                    if isOffline { WatchOfflineBadge(since: store.receivedAt, now: context.date) }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    ["Monitor", metric.label, "\(percent) por cento",
                     isOffline ? "sem iPhone, atualizado \(WatchOfflineBadge.ago(store.receivedAt, now: context.date, spoken: true))" : nil]
                        .compactMap { $0 }
                        .joined(separator: ", ")
                )
        }
    }

    private func ring(metric: StWatchMetric, value: Double, percent: Int, detail: String) -> some View {
        let monitor = StTool.monitor
        return StDialRing(
            size: diameter,
            fraction: value,
            ringColor: metric.ringRGB(value).color,
            trackColor: monitor.opacity(0.12),
            tickColor: monitor.secondaryRGB.color(opacity: 0.5),
            halo: isLuminanceReduced ? [.init(color: .clear, location: 0)] : [
                .init(color: monitor.opacity(0.24), location: 0),
                .init(color: monitor.secondaryRGB.color(opacity: 0.10), location: 0.5),
                .init(color: monitor.opacity(0), location: 0.7)
            ]
        ) {
            VStack(spacing: 2) {
                Text(metric.label.uppercased())
                    .font(StFont.body(WatchType.label(diameter), .heavy))
                    .tracking(1.3)
                    .foregroundStyle(metric.labelRGB.color)
                StBigNumber(value: percent, unit: .percent, size: WatchType.number(diameter))
                Text(detail.isEmpty ? " " : detail)
                    .font(StFont.body(WatchType.caption(diameter)))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }
}

// MARK: - Offline

/// "Sem iPhone · há 2 min": Âmbar on a 16% fill, 18 pt, at the foot of the page.
struct WatchOfflineBadge: View {
    let since: Date?
    let now: Date

    var body: some View {
        Text("Sem iPhone · \(Self.ago(since, now: now, spoken: false))")
            .font(StFont.body(11, .bold))
            .foregroundStyle(StTool.fx.tone)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 10)
            .frame(height: 18)
            .background(Capsule().fill(StTool.fx.tint))
            // Centered in the ≈ 21–24 pt band under the circle (v0.10.1).
            .padding(.bottom, 3)
            .accessibilityHidden(true)
    }

    /// "há 40 s", "há 2 min", "há 3 h" (spoken: "há 2 minutos").
    static func ago(_ date: Date?, now: Date, spoken: Bool) -> String {
        guard let date else { return spoken ? "nunca" : "sem dados" }
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return spoken ? "há \(seconds) segundos" : "há \(seconds) s" }
        let minutes = seconds / 60
        if minutes < 60 { return spoken ? "há \(minutes) \(minutes == 1 ? "minuto" : "minutos")" : "há \(minutes) min" }
        let hours = minutes / 60
        return spoken ? "há \(hours) \(hours == 1 ? "hora" : "horas")" : "há \(hours) h"
    }
}
