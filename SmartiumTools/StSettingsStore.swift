//
//  StSettingsStore.swift
//  SmartiumTools
//
//  App preferences (handoff v0.3): `tabOrder` and `monitor`, synced between
//  devices through the iCloud `settings.json` (next to `limitimer`).
//  `Application Support/<bundle id>/settings.json` is a local cache, so launch
//  and offline use keep the last values. The future Settings screen edits this
//  store. App-only: excluded from SmartiumWidgetsExtension.
//

import Foundation
import Observation
import OSLog

nonisolated struct StSettings: Codable, Equatable, Sendable {
  struct Monitor: Codable, Equatable, Sendable {
    /// `"memory" | "disk" | "gpu" | "battery"`, or nil for CPU in the hero.
    var pinnedMetric: String?
    /// Sampling interval in seconds.
    var interval: Double

    init(pinnedMetric: String? = nil, interval: Double = 1.0) {
      self.pinnedMetric = pinnedMetric
      self.interval = interval
    }

    init(from decoder: Decoder) throws {
      let values = try decoder.container(keyedBy: CodingKeys.self)
      pinnedMetric = try values.decodeIfPresent(String.self, forKey: .pinnedMetric)
      interval = try values.decodeIfPresent(Double.self, forKey: .interval) ?? 1.0
    }

    func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      // Written as `null` when unpinned, like the handoff's example.
      try container.encode(pinnedMetric, forKey: .pinnedMetric)
      try container.encode(interval, forKey: .interval)
    }

    private enum CodingKeys: String, CodingKey {
      case pinnedMetric, interval
    }
  }

  /// Tool IDs in tab order. Tools missing from the list go at the end.
  var tabOrder: [String]
  var monitor: Monitor

  init(tabOrder: [String] = [], monitor: Monitor = Monitor()) {
    self.tabOrder = tabOrder
    self.monitor = monitor
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    tabOrder = try values.decodeIfPresent([String].self, forKey: .tabOrder) ?? []
    monitor = try values.decodeIfPresent(Monitor.self, forKey: .monitor) ?? Monitor()
  }

  private enum CodingKeys: String, CodingKey {
    case tabOrder, monitor
  }
}

@Observable
final class StSettingsStore {
  static let shared = StSettingsStore()

  var settings: StSettings {
    didSet {
      guard settings != oldValue else { return }
      writeCache()
      if !isApplyingICloud {
        pushToICloud()
      }
    }
  }

  @ObservationIgnored private let cacheURL: URL?
  @ObservationIgnored private var isApplyingICloud = false
  /// Pushes run one after another, so the last change is the one iCloud keeps.
  @ObservationIgnored private var pushTask: Task<Void, Never>?
  @ObservationIgnored private let logger = Logger(subsystem: "dev.smartium.tools", category: "settings")

  init() {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    let folder = base?.appendingPathComponent(Bundle.main.bundleIdentifier ?? "SmartiumTools", isDirectory: true)
    cacheURL = folder?.appendingPathComponent("settings.json")
    settings = Self.read(cacheURL) ?? StSettings()
  }

  /// `items` in `tabOrder`, then any item not listed, in its original order.
  func ordered<Item>(_ items: [Item], id: (Item) -> String) -> [Item] {
    let rank = Dictionary(uniqueKeysWithValues: settings.tabOrder.enumerated().map { ($1, $0) })
    return items.enumerated()
      .sorted { lhs, rhs in
        let left = rank[id(lhs.element)] ?? settings.tabOrder.count + lhs.offset
        let right = rank[id(rhs.element)] ?? settings.tabOrder.count + rhs.offset
        return left < right
      }
      .map(\.element)
  }

  /// Takes the iCloud values when the file has them (another device may have
  /// changed them); otherwise publishes this device's values. Called when the
  /// scene becomes active.
  func syncWithICloud() async {
    await pushTask?.value
    switch await ICloudSettings.loadAppSettings() {
    case .found(let remote):
      isApplyingICloud = true
      settings = remote
      isApplyingICloud = false
    case .absent:
      pushToICloud()
    case .unavailable:
      break
    }
  }

  private func pushToICloud() {
    let settings = settings
    let previous = pushTask
    pushTask = Task {
      await previous?.value
      await ICloudSettings.saveAppSettings(settings)
    }
  }

  private static func read(_ url: URL?) -> StSettings? {
    guard let url, let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONDecoder().decode(StSettings.self, from: data)
  }

  private func writeCache() {
    guard let cacheURL else { return }
    do {
      try FileManager.default.createDirectory(
        at: cacheURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      try encoder.encode(settings).write(to: cacheURL, options: .atomic)
    } catch {
      logger.error("Falha ao salvar o cache de ajustes: \(error.localizedDescription, privacy: .public)")
    }
  }
}
