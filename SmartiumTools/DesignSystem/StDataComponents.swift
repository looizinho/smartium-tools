//
//  StDataComponents.swift
//  SmartiumTools
//
//  Data components (handoff v0.1). No screen uses them yet; they are shown
//  only in #Preview until a tool needs them.
//

import Charts
import SwiftUI

// MARK: - StRing

/// Status ring. `.large`: stroke 9 at r40. `.small`: stroke 6 at r22.
struct StRing: View {
    enum Size {
        case large
        case small

        var radius: CGFloat { self == .large ? 40 : 22 }
        var lineWidth: CGFloat { self == .large ? 9 : 6 }
        var fontSize: CGFloat { self == .large ? 22 : 13 }
    }

    /// 0–1.
    let value: Double
    var size: Size = .large

    var body: some View {
        let fraction = min(max(value, 0), 1)
        let status = StStatus(fraction: fraction)
        let diameter = (size.radius + size.lineWidth / 2) * 2
        ZStack {
            Circle()
                .stroke(status.tint, lineWidth: size.lineWidth)
                .padding(size.lineWidth / 2)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(status.tone, style: StrokeStyle(lineWidth: size.lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(size.lineWidth / 2)
            Text("\(Int((fraction * 100).rounded()))%")
                .font(StFont.body(size.fontSize, .bold))
                .monospacedDigit()
                .foregroundStyle(status.tone)
        }
        .frame(width: diameter, height: diameter)
        .animation(.easeInOut(duration: 0.6), value: fraction)
        .accessibilityElement()
        .accessibilityValue("\(Int((fraction * 100).rounded())) %")
    }
}

// MARK: - StMeter

/// Status bar: h8, radius 4, over `ink.600`.
struct StMeter: View {
    /// 0–1.
    let value: Double
    var height: CGFloat = 8

    var body: some View {
        let fraction = min(max(value, 0), 1)
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.stInk600)
                Capsule()
                    .fill(StStatus(fraction: fraction).tone)
                    .frame(width: proxy.size.width * fraction)
            }
        }
        .frame(height: height)
        .clipShape(Capsule())
        .animation(.easeInOut(duration: 0.6), value: fraction)
    }
}

// MARK: - StSegMeter

/// 32 segments h10, radius 3, gap 3. Filled segments use the status color.
struct StSegMeter: View {
    /// 0–1.
    let value: Double
    var segments = 32

    var body: some View {
        let fraction = min(max(value, 0), 1)
        let filled = Int((fraction * Double(segments)).rounded())
        let tone = StStatus(fraction: fraction).tone
        HStack(spacing: 3) {
            ForEach(0..<segments, id: \.self) { index in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(index < filled ? tone : Color.stInk600)
                    .frame(height: 10)
            }
        }
    }
}

// MARK: - Sparkline

/// Series-1 sparkline with a tinted area.
struct StSparkline: View {
    let values: [Double]
    var range: ClosedRange<Double> = 0...1

    var body: some View {
        Chart(Array(values.enumerated()), id: \.offset) { item in
            AreaMark(x: .value("t", item.offset), y: .value("v", item.element))
                .foregroundStyle(StTool.orb.tint)
            LineMark(x: .value("t", item.offset), y: .value("v", item.element))
                .foregroundStyle(StTool.orb.tone)
                .lineStyle(StrokeStyle(lineWidth: 2, lineJoin: .round))
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: range)
        .chartLegend(.hidden)
    }
}

// MARK: - StMetricTile

/// Tile + value 26 + series-1 sparkline h36 + status mini bar h6.
struct StMetricTile: View {
    let title: LocalizedStringKey
    let subtitle: String
    let systemImage: String
    /// Current value, 0–1.
    let value: Double
    /// History, 0–1.
    let history: [Double]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                StIconTile(systemImage, tool: .orb, size: 36)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(StFont.body(15, .semibold))
                    Text(subtitle)
                        .font(StFont.body(12))
                        .foregroundStyle(Color.stTextTertiary)
                }
                .lineLimit(1)
            }
            Text("\(Int((value * 100).rounded()))%")
                .font(StFont.body(26, .bold))
                .monospacedDigit()
            StSparkline(values: history)
                .frame(height: 36)
            StMeter(value: value, height: 6)
        }
        .foregroundStyle(Color.stTextPrimary)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.stInk700))
    }
}

// MARK: - StQuickTile

/// Shortcut + count. Tile and number use the tool color, never a status color.
struct StQuickTile: View {
    let title: LocalizedStringKey
    let systemImage: String
    let tool: StTool
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                StIconTile(systemImage, tool: tool)
                Spacer()
                Text("\(count)")
                    .font(StFont.body(20, .bold))
                    .monospacedDigit()
                    .foregroundStyle(tool.tone)
            }
            Text(title)
                .font(StFont.body(16, .semibold))
                .foregroundStyle(Color.stTextPrimary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.stInk700))
    }
}

// MARK: - StAreaChart

struct StChartSeries: Identifiable {
    let id = UUID()
    let name: String
    /// Values in the chart's Y range, oldest first.
    let values: [Double]
}

/// Up to 3 series. Series 1 gets the area fill; dashed Y grid only; the
/// latest series-1 value is marked with a point and a 4pt halo.
struct StAreaChart: View {
    let series: [StChartSeries]
    var yDomain: ClosedRange<Double> = 0...100
    var yTicks: [Double] = [0, 50, 100]

    private struct Point: Identifiable {
        let id: String
        let seriesIndex: Int
        let x: Int
        let y: Double
    }

    private var points: [Point] {
        series.prefix(3).enumerated().flatMap { seriesIndex, item in
            item.values.enumerated().map { x, y in
                Point(id: "\(seriesIndex)-\(x)", seriesIndex: seriesIndex, x: x, y: y)
            }
        }
    }

    var body: some View {
        let series1 = series.first?.values ?? []
        Chart {
            // Draw series 3 → 1 so series 1 ends on top.
            ForEach(points.reversed()) { point in
                if point.seriesIndex == 0 {
                    AreaMark(
                        x: .value("t", point.x),
                        yStart: .value("base", yDomain.lowerBound),
                        yEnd: .value("v", point.y),
                        series: .value("s", "area")
                    )
                    .foregroundStyle(StTool.orb.tint)
                }
                LineMark(
                    x: .value("t", point.x),
                    y: .value("v", point.y),
                    series: .value("s", point.seriesIndex)
                )
                .foregroundStyle(StSeriesColor.color(at: point.seriesIndex))
                .lineStyle(StrokeStyle(lineWidth: [2.4, 2, 1.8][point.seriesIndex], lineJoin: .round))
            }
            if let last = series1.last {
                PointMark(x: .value("t", series1.count - 1), y: .value("v", last))
                    .symbolSize(196)
                    .foregroundStyle(StTool.orb.opacity(0.25))
                PointMark(x: .value("t", series1.count - 1), y: .value("v", last))
                    .symbolSize(100)
                    .foregroundStyle(StTool.orb.tone)
            }
        }
        .chartXAxis(.hidden)
        .chartYScale(domain: yDomain)
        .chartYAxis {
            AxisMarks(position: .leading, values: yTicks) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [2, 5]))
                    .foregroundStyle(Color.stTextPrimary.opacity(0.12))
                AxisValueLabel {
                    if let number = value.as(Double.self), number == yTicks[yTicks.count / 2] {
                        Text("\(Int(number))%")
                            .font(StFont.body(11))
                            .foregroundStyle(Color.stTextQuaternary)
                    }
                }
            }
        }
        .chartLegend(.hidden)
    }
}

/// Legend pill: color bar + "Name value%".
struct StLegendPill: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Capsule().fill(color).frame(width: 12, height: 4)
            Text(text)
                .font(StFont.body(12, .semibold))
                .monospacedDigit()
        }
        .foregroundStyle(Color.stTextPrimary)
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(Capsule().fill(Color.stInk600))
    }
}

// MARK: - StHostCard

struct StHostMetric: Identifiable {
    let id = UUID()
    let label: String
    let detail: String
    /// 0–1.
    let value: Double
}

struct StHostCard: View {
    enum Status {
        case online(
            uptime: String,
            metrics: [StHostMetric],
            downloadKBps: Int,
            uploadKBps: Int,
            networkHistory: [Double]
        )
        case error(title: String, log: String)
    }

    let name: String
    let subtitle: String
    let systemImage: String
    let status: Status

    var body: some View {
        switch status {
        case .online(let uptime, let metrics, let down, let up, let history):
            VStack(alignment: .leading, spacing: 16) {
                header(uptime: uptime, isOnline: true)
                HStack(spacing: 8) {
                    ForEach(metrics.prefix(3)) { metric in
                        VStack(spacing: 6) {
                            Text(metric.label)
                                .font(StFont.body(12))
                                .foregroundStyle(Color.stTextPrimary.opacity(0.55))
                            StRing(value: metric.value, size: .small)
                            Text(metric.detail)
                                .font(StFont.body(12))
                                .foregroundStyle(Color.stTextTertiary)
                        }
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 4)
                        .frame(maxWidth: .infinity)
                        .background(well)
                    }
                    networkWell(down: down, up: up, history: history)
                        .layoutPriority(1)
                }
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: StTool.orb.opacity(0.12), location: 0),
                                .init(color: .stInk700, location: 0.55)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )

        case .error(let title, let log):
            VStack(alignment: .leading, spacing: 14) {
                header(uptime: nil, isOnline: false)
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(StFont.body(18))
                        .foregroundStyle(StTool.fx.tone)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(StFont.body(14, .semibold))
                            .foregroundStyle(StTool.fx.tone)
                        Text(log)
                            .font(StFont.body(12))
                            .foregroundStyle(Color.stTextPrimary.opacity(0.55))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(StTool.fx.opacity(0.10))
                )
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Color.stInk700))
        }
    }

    private var well: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Color.stInk900.opacity(0.45))
    }

    private func header(uptime: String?, isOnline: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(StFont.body(20, .semibold))
                .foregroundStyle(isOnline ? StTool.orb.tone : Color.stTextPrimary.opacity(0.6))
                .frame(width: 48, height: 48)
                .background(Circle().fill(isOnline ? StTool.orb.opacity(0.18) : Color.stInk600))
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(StFont.body(18, .semibold))
                    .foregroundStyle(Color.stTextPrimary)
                HStack(spacing: 6) {
                    Circle()
                        .fill(isOnline ? StTool.timer.tone : Color.stTextPrimary.opacity(0.38))
                        .frame(width: 7, height: 7)
                    Text(subtitle)
                        .font(StFont.body(13))
                        .foregroundStyle(Color.stTextPrimary.opacity(0.55))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let uptime {
                Text(uptime)
                    .font(StFont.body(13))
                    .foregroundStyle(Color.stTextTertiary)
            }
            Image(systemName: "chevron.right")
                .font(StFont.body(13, .semibold))
                .foregroundStyle(Color.stTextQuaternary)
        }
    }

    private func networkWell(down: Int, up: Int, history: [Double]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Rede")
                .font(StFont.body(12))
                .foregroundStyle(Color.stTextPrimary.opacity(0.55))
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("↓").foregroundStyle(StTool.orb.tone)
                    Text("\(down) K/s")
                }
                HStack(spacing: 6) {
                    Text("↑").foregroundStyle(Color.stBrand)
                    Text("\(up) K/s")
                }
            }
            .font(StFont.body(13, .semibold))
            .monospacedDigit()
            .foregroundStyle(Color.stTextPrimary)
            .lineLimit(1)
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(history.suffix(12).enumerated()), id: \.offset) { _, value in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(StTool.orb.tone)
                        .frame(height: max(2, 18 * min(max(value, 0), 1)))
                }
            }
            .frame(height: 18, alignment: .bottom)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(well)
    }
}

// MARK: - Previews

private enum StPreviewData {
    static func wave(_ count: Int, base: Double, amplitude: Double, phase: Double) -> [Double] {
        (0..<count).map { index in
            let x = Double(index) / 4 + phase
            return base + amplitude * sin(x) + amplitude * 0.4 * sin(x * 2.7)
        }
    }
}

#Preview("Dados") {
    ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 18) {
                StRing(value: 0.42)
                StRing(value: 0.74)
                StRing(value: 0.93)
                StRing(value: 0.55, size: .small)
            }
            StMeter(value: 0.68)
            StSegMeter(value: 0.9)
            HStack(spacing: 10) {
                StMetricTile(
                    title: "CPU",
                    subtitle: "8 núcleos",
                    systemImage: "cpu",
                    value: 0.46,
                    history: StPreviewData.wave(24, base: 0.45, amplitude: 0.15, phase: 0)
                )
                StMetricTile(
                    title: "Memória",
                    subtitle: "8 GB",
                    systemImage: "memorychip",
                    value: 0.81,
                    history: StPreviewData.wave(24, base: 0.7, amplitude: 0.1, phase: 1)
                )
            }
            HStack(spacing: 10) {
                StQuickTile(title: "Orb", systemImage: "sparkles", tool: .orb, count: 50)
                StQuickTile(title: "Timers", systemImage: "timer", tool: .timer, count: 12)
            }
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    StTag("Ao vivo", tool: .timer)
                    Text("CPU · A17 Pro")
                        .font(StFont.body(14))
                        .foregroundStyle(Color.stTextTertiary)
                }
                HStack(spacing: 6) {
                    StLegendPill(text: "Total 48%", color: StSeriesColor.color(at: 0))
                    StLegendPill(text: "Usuário 31%", color: StSeriesColor.color(at: 1))
                    StLegendPill(text: "Sistema 17%", color: StSeriesColor.color(at: 2))
                }
                StAreaChart(series: [
                    StChartSeries(name: "Total", values: StPreviewData.wave(60, base: 48, amplitude: 12, phase: 0)),
                    StChartSeries(name: "Usuário", values: StPreviewData.wave(60, base: 31, amplitude: 9, phase: 0.6)),
                    StChartSeries(name: "Sistema", values: StPreviewData.wave(60, base: 17, amplitude: 5, phase: 1.3))
                ])
                .frame(height: 170)
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Color.stInk700))

            StHostCard(
                name: "Macintosh",
                subtitle: "MacBook Pro · M1",
                systemImage: "laptopcomputer",
                status: .online(
                    uptime: "13h 29m",
                    metrics: [
                        StHostMetric(label: "CPU", detail: "8 núcleos", value: 0.38),
                        StHostMetric(label: "Memória", detail: "8 GB", value: 0.72),
                        StHostMetric(label: "Disco", detail: "1,5 TB", value: 0.18)
                    ],
                    downloadKBps: 412,
                    uploadKBps: 38,
                    networkHistory: StPreviewData.wave(12, base: 0.5, amplitude: 0.3, phase: 0)
                )
            )
            StHostCard(
                name: "Servidor Ubuntu",
                subtitle: "Indisponível · Docker",
                systemImage: "server.rack",
                status: .error(title: "Docker não encontrado", log: "zsh:1: command not found: docker")
            )
        }
        .padding(20)
    }
    .background(Color.stInk900)
    .foregroundStyle(Color.stTextPrimary)
    .preferredColorScheme(.dark)
}
