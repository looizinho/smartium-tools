//
//  StMonitorModel.swift
//  SmartiumTools
//
//  Samples `LiveMetricsProvider` at the chosen interval and fills any metric
//  it cannot read from `SimulatedMetricsProvider` (handoff v0.3).
//  App-only: excluded from SmartiumWidgetsExtension.
//

import Foundation
import Observation

/// A value and whether it came from the simulated provider (`SIM` badge).
struct StMetric<Value> {
  var value: Value
  var isSimulated: Bool
}

/// Metrics that can be pinned to the hero (iOS) and their `settings.json` key.
enum StPinnedMetric: String, CaseIterable {
  case memory, disk, gpu, battery
}

@Observable
final class StMonitorModel {
  /// Samples kept per core for the heatmap.
  static let historyLength = 30

  private(set) var coreNames: [String] = []
  /// Per-core history in display order, oldest first.
  private(set) var coreHistory: [[Double]] = []
  private(set) var cpu = StMetric(value: 0.0, isSimulated: false)
  private(set) var memory = StMetric(value: StCapacityReading(used: 0, total: 0), isSimulated: false)
  private(set) var disk = StMetric(value: StCapacityReading(used: 0, total: 0), isSimulated: false)
  private(set) var gpu = StMetric(value: 0.0, isSimulated: true)
  /// nil when the Mac has no battery (the card is hidden).
  private(set) var battery: StMetric<StBatteryReading>?
  private(set) var network = StMetric(value: StNetworkReading(download: 0, upload: 0), isSimulated: false)
  /// Highest rates seen this session; the bars are relative to them.
  private(set) var peakDownload = 0.0
  private(set) var peakUpload = 0.0
  private(set) var thermal = StMetric(value: ProcessInfo.ThermalState.nominal, isSimulated: false)
  private(set) var hasSample = false

  @ObservationIgnored private let live: StMetricsProvider = LiveMetricsProvider()
  @ObservationIgnored private let simulated: StMetricsProvider = SimulatedMetricsProvider()
  @ObservationIgnored private var lastWidgetReload: Date?

  /// Samples until the task is cancelled. Restart it to change the interval.
  func run(interval: Double) async {
    while !Task.isCancelled {
      sample()
      try? await Task.sleep(for: .seconds(interval))
    }
  }

  private func pick<Value>(_ live: Value?, _ simulated: () -> Value?) -> StMetric<Value>? {
    if let live { return StMetric(value: live, isSimulated: false) }
    return simulated().map { StMetric(value: $0, isSimulated: true) }
  }

  private func sample() {
    if let reading = pick(live.cpu(), simulated.cpu) {
      appendCores(reading.value.cores, isSimulated: reading.isSimulated)
      cpu = StMetric(value: reading.value.total, isSimulated: reading.isSimulated)
    }
    if let value = pick(live.memory(), simulated.memory) { memory = value }
    if let value = pick(live.disk(), simulated.disk) { disk = value }
    if let value = pick(live.gpu(), simulated.gpu) { gpu = value }
#if os(macOS)
    // A Mac without a battery has nothing to show; don't simulate one.
    battery = live.battery().map { StMetric(value: $0, isSimulated: false) }
#else
    battery = pick(live.battery(), simulated.battery)
#endif
    if let value = pick(live.network(), simulated.network) {
      network = value
      peakDownload = max(peakDownload, value.value.download)
      peakUpload = max(peakUpload, value.value.upload)
    }
    if let value = pick(live.thermal(), simulated.thermal) { thermal = value }
    hasSample = true
    publishSnapshot()
  }

  /// Saves the sample for the Monitor widgets and control (v0.5). Widgets
  /// reload at most once a minute; their own timeline refreshes every 15 min.
  private func publishSnapshot() {
    let snapshot = StMetricsSnapshot(
      cpu: cpu.value,
      gpu: gpu.value,
      memory: memory.value.fraction,
      disk: disk.value.fraction,
      updatedAt: .now,
      battery: battery?.value.level,
      batteryCharging: battery?.value.isCharging,
      cores: coreNames.isEmpty ? nil : coreNames.count,
      interval: StSettingsStore.shared.settings.monitor.interval
    )
    StLiveSurfaces.metrics = snapshot
#if os(iOS)
    // Live samples to an open watch app (v0.10).
    StWatchSync.shared.metricsSampled(
      snapshot,
      detail: heroDetail(pinned: StSettingsStore.shared.settings.monitor.pinnedMetric)
    )
#endif
    if let lastWidgetReload, Date.now.timeIntervalSince(lastWidgetReload) < 60 { return }
    lastWidgetReload = .now
    StLiveSurfaces.reloadMonitor()
  }

  // MARK: Captions

  /// Caption under the hero number for the pinned metric (nil: CPU), as on
  /// the iPhone hero.
  func heroDetail(pinned: String?) -> String {
    switch pinned.flatMap(StPinnedMetric.init(rawValue:)) {
    case .memory: Self.memorySubtitle(memory.value)
    case .disk: Self.diskSubtitle(disk.value)
    case .gpu: "Estimado"
    case .battery: battery.map { $0.value.isCharging ? "Carregando" : "Na bateria" } ?? ""
    case nil: "\(coreNames.count) núcleos"
    }
  }

  nonisolated private static func decimal(_ value: Double, digits: Int) -> String {
    String(format: "%.\(digits)f", value).replacingOccurrences(of: ".", with: ",")
  }

  /// "6,5 de 8 GB" (binary gigabytes, like the system's memory size).
  static func memorySubtitle(_ reading: StCapacityReading) -> String {
    let gib = 1_073_741_824.0
    let total = reading.total / gib
    let totalText = total.rounded() == total ? String(Int(total)) : decimal(total, digits: 1)
    return "\(decimal(reading.used / gib, digits: 1)) de \(totalText) GB"
  }

  /// "362 de 512 GB" (decimal gigabytes, like storage sizes).
  static func diskSubtitle(_ reading: StCapacityReading) -> String {
    "\(Int((reading.used / 1e9).rounded())) de \(Int((reading.total / 1e9).rounded())) GB"
  }

  private func appendCores(_ cores: [Double], isSimulated: Bool) {
    let rows: [(name: String, index: Int)] = isSimulated
      ? ["P1", "P2", "E1", "E2", "E3", "E4"].prefix(cores.count).enumerated().map { ($1, $0) }
      : StCoreLayout.rows(coreCount: cores.count)
    if coreNames != rows.map(\.name) {
      coreNames = rows.map(\.name)
      coreHistory = rows.map { _ in [] }
    }
    coreHistory = zip(coreHistory, rows).map { history, row in
      Array((history + [cores[row.index]]).suffix(Self.historyLength))
    }
  }
}
