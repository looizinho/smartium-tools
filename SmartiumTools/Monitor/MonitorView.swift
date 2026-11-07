//
//  MonitorView.swift
//  SmartiumTools
//
//  Monitor tool (handoff v0.3): one ring in the hero on iPhone (CPU, or the
//  pinned metric), a 2×2 grid of rings on the Mac, then gauges, cores,
//  network, thermal state and the sampling interval.
//  App-only: excluded from SmartiumWidgetsExtension.
//

import SwiftUI

struct MonitorView: View {
  @State private var model = StMonitorModel()
  @Environment(\.stLayoutMode) private var mode
  @Environment(\.stIsActiveTab) private var isActiveTab
  private var store = StSettingsStore.shared

  private static let intervals: [Double] = [0.5, 1, 2, 5]

  private var interval: Double {
    store.settings.monitor.interval
  }

  /// Pinning exists only on iPhone; the Mac shows four rings instead.
  private var pinned: StPinnedMetric? {
    guard mode != .mac else { return nil }
    return store.settings.monitor.pinnedMetric.flatMap(StPinnedMetric.init(rawValue:))
  }

  var body: some View {
    StAdaptiveToolLayout(tool: .monitor, tag: "Monitor") { size in
      if mode == .mac {
        quadHero
      } else {
        singleHero(size: size)
      }
    } controls: {
      StToolHeader(
        title: "Monitor",
        subtitle: "Ao vivo · a cada \(Self.intervalLabel(interval))",
        tool: .monitor,
        status: .active
      )

      gaugeGrid

      StHeatmap(
        title: "Núcleos · \(StMonitorModel.historyLength) amostras",
        value: model.cpu.value,
        rows: zip(model.coreNames, model.coreHistory).map { StHeatmap.Row(name: $0, values: $1) }
      )

      StRateCard(items: [
        StRateCard.Item(
          label: "Download",
          systemImage: "arrow.down",
          color: StAccent.sky.color,
          value: Self.megabytes(model.network.value.download),
          unit: "MB/s",
          fraction: Self.share(model.network.value.download, of: model.peakDownload)
        ),
        StRateCard.Item(
          label: "Upload",
          systemImage: "arrow.up",
          color: .stBrand,
          value: Self.megabytes(model.network.value.upload),
          unit: "MB/s",
          fraction: Self.share(model.network.value.upload, of: model.peakUpload)
        )
      ])

      StStepMeter(
        title: "Estado térmico",
        levels: [
          ("Nominal", StTool.timer.tone),
          ("Razoável", StTool.fx.tone),
          ("Sério", StTool.voice.tone),
          ("Crítico", .stBrand)
        ],
        level: model.thermal.value.rawValue
      )

      StChipSection(
        title: "Intervalo",
        dot: StTool.monitor.secondary,
        items: Self.intervals,
        label: Self.intervalLabel,
        color: Self.intervalColor,
        isOn: { $0 == interval },
        select: { store.settings.monitor.interval = $0 }
      )
    }
    // Samples only while the tab is visible (v0.9.2).
    .task(id: SamplingKey(interval: interval, isActive: isActiveTab)) {
      guard isActiveTab else { return }
      await model.run(interval: interval)
    }
  }

  // MARK: Hero

  private func singleHero(size: CGFloat) -> some View {
    let monitor = StTool.monitor
    let gauge = pinned.flatMap { metric in gauges.first { $0.metric == metric } }
    let value = gauge?.value ?? model.cpu.value
    return StDialRing(
      size: size,
      fraction: value,
      ringColor: gauge?.color ?? StStatus(fraction: value).tone,
      trackColor: monitor.opacity(0.12),
      tickColor: monitor.secondaryRGB.color(opacity: 0.5),
      halo: [
        .init(color: monitor.opacity(0.24), location: 0),
        .init(color: monitor.secondaryRGB.color(opacity: 0.10), location: 0.5),
        .init(color: monitor.opacity(0), location: 0.7)
      ]
    ) {
      VStack(spacing: 2) {
        Text(gauge?.label.uppercased() ?? "CPU")
          .font(.stTag)
          .tracking(1.4)
          .foregroundStyle(gauge?.metric.heroLabelColor ?? monitor.tone)
        StBigNumber(value: Int((value * 100).rounded()), unit: .percent, size: (size * 0.2).rounded())
        Text(gauge?.subtitle ?? "\(model.coreNames.count) núcleos")
          .font(StFont.body(13))
          .foregroundStyle(Color.stTextPrimary.opacity(0.55))
          .lineLimit(1)
      }
      .accessibilityElement(children: .combine)
    }
    .animation(.easeInOut(duration: 0.4), value: pinned)
  }

  /// Mac hero: CPU, memory, disk and GPU rings, each with its own halo color.
  private var quadHero: some View {
    let rings: [(label: String, value: Double, subtitle: String, color: StRGB, isSimulated: Bool)] = [
      ("CPU", model.cpu.value, "\(model.coreNames.count) núcleos", StAccent.sky, model.cpu.isSimulated),
      ("Memória", model.memory.value.fraction, Self.memorySubtitle(model.memory.value), StTool.orb.rgb, model.memory.isSimulated),
      ("Disco", model.disk.value.fraction, Self.diskSubtitle(model.disk.value), StAccent.brand, model.disk.isSimulated),
      ("GPU", model.gpu.value, "Estimado", StTool.timer.rgb, model.gpu.isSimulated)
    ]
    return LazyVGrid(
      columns: [GridItem(.flexible(), spacing: 28), GridItem(.flexible(), spacing: 28)],
      spacing: 28
    ) {
      ForEach(rings, id: \.label) { ring in
        GeometryReader { proxy in
          StDialRing(
            size: proxy.size.width,
            fraction: ring.value,
            ringColor: StStatus(fraction: ring.value).tone,
            trackColor: ring.color.color(opacity: 0.14),
            tickColor: ring.color.color(opacity: 0.5),
            lineWidth: 6,
            tickRadius: 36,
            halo: [
              .init(color: ring.color.color(opacity: 0.22), location: 0),
              .init(color: ring.color.color(opacity: 0), location: 0.68)
            ],
            haloInset: 0.08
          ) {
            VStack(spacing: 4) {
              HStack(spacing: 6) {
                Text(ring.label.uppercased())
                  .font(.stTag)
                  .tracking(1.4)
                  .foregroundStyle(ring.color.color)
                if ring.isSimulated {
                  StSimBadge()
                }
              }
              StBigNumber(value: Int((ring.value * 100).rounded()), unit: .percent, size: 40)
              Text(ring.subtitle)
                .font(StFont.body(12))
                .foregroundStyle(Color.stTextPrimary.opacity(0.55))
                .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
          }
        }
        .aspectRatio(1, contentMode: .fit)
      }
    }
    .frame(maxWidth: 480)
    .padding(24)
  }

  // MARK: Gauges

  private struct Gauge {
    let metric: StPinnedMetric
    let label: String
    let value: Double
    let subtitle: String
    let color: Color
    let isSimulated: Bool
  }

  private var gauges: [Gauge] {
    var gauges = [
      Gauge(
        metric: .memory, label: "Memória", value: model.memory.value.fraction,
        subtitle: Self.memorySubtitle(model.memory.value),
        color: StStatus(fraction: model.memory.value.fraction).tone,
        isSimulated: model.memory.isSimulated
      ),
      Gauge(
        metric: .disk, label: "Disco", value: model.disk.value.fraction,
        subtitle: Self.diskSubtitle(model.disk.value),
        color: StStatus(fraction: model.disk.value.fraction).tone,
        isSimulated: model.disk.isSimulated
      ),
      Gauge(
        metric: .gpu, label: "GPU", value: model.gpu.value,
        subtitle: "Estimado",
        color: StStatus(fraction: model.gpu.value).tone,
        isSimulated: model.gpu.isSimulated
      )
    ]
    if let battery = model.battery {
      let level = battery.value.level
      gauges.append(Gauge(
        metric: .battery, label: "Bateria", value: level,
        subtitle: battery.value.isCharging ? "Carregando" : "Na bateria",
        // Inverted: low battery is the alert.
        color: level < 0.2 ? StTool.voice.tone : level < 0.4 ? StTool.fx.tone : StTool.timer.tone,
        isSimulated: battery.isSimulated
      ))
    }
    return gauges
  }

  /// iPhone: all gauges in two columns, tappable to pin. Mac: only the battery.
  @ViewBuilder
  private var gaugeGrid: some View {
    let isMac = mode == .mac
    let visible = isMac ? gauges.filter { $0.metric == .battery } : gauges
    if !visible.isEmpty {
      LazyVGrid(
        columns: isMac
          ? [GridItem(.flexible())]
          : [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
        spacing: 10
      ) {
        ForEach(visible, id: \.metric) { gauge in
          StGaugeTile(
            label: gauge.label,
            value: gauge.value,
            subtitle: gauge.subtitle,
            color: gauge.color,
            isSimulated: gauge.isSimulated,
            isPinned: pinned == gauge.metric,
            action: isMac ? nil : { togglePin(gauge.metric) }
          )
        }
      }
    }
  }

  private func togglePin(_ metric: StPinnedMetric) {
    store.settings.monitor.pinnedMetric = pinned == metric ? nil : metric.rawValue
  }

  // MARK: Formatting

  nonisolated private static func decimal(_ value: Double, digits: Int) -> String {
    String(format: "%.\(digits)f", value).replacingOccurrences(of: ".", with: ",")
  }

  /// "6,5 de 8 GB" (binary gigabytes, like the system's memory size).
  private static func memorySubtitle(_ reading: StCapacityReading) -> String {
    let gib = 1_073_741_824.0
    let total = reading.total / gib
    let totalText = total.rounded() == total ? String(Int(total)) : decimal(total, digits: 1)
    return "\(decimal(reading.used / gib, digits: 1)) de \(totalText) GB"
  }

  /// "362 de 512 GB" (decimal gigabytes, like storage sizes).
  private static func diskSubtitle(_ reading: StCapacityReading) -> String {
    "\(Int((reading.used / 1e9).rounded())) de \(Int((reading.total / 1e9).rounded())) GB"
  }

  private static func megabytes(_ bytesPerSecond: Double) -> String {
    decimal(bytesPerSecond / 1e6, digits: 1)
  }

  private static func share(_ value: Double, of peak: Double) -> Double {
    peak > 0 ? value / peak : 0
  }

  nonisolated static func intervalLabel(_ seconds: Double) -> String {
    (seconds.rounded() == seconds ? String(Int(seconds)) : decimal(seconds, digits: 1)) + " s"
  }

  nonisolated private static func intervalColor(_ seconds: Double) -> StRGB {
    switch seconds {
    case 0.5: StAccent.sky
    case 1: StTool.timer.rgb
    case 2: StTool.fx.rgb
    default: StTool.orb.rgb
    }
  }
}

private extension StPinnedMetric {
  /// Hero label color when pinned.
  var heroLabelColor: Color {
    switch self {
    case .memory: StTool.orb.tone
    case .disk: .stBrand
    case .gpu: StTool.timer.tone
    case .battery: StTool.fx.tone
    }
  }
}

/// Restarts sampling when the interval or the tab's visibility changes.
private struct SamplingKey: Equatable {
  let interval: Double
  let isActive: Bool
}
