//
//  StMetricsProvider.swift
//  SmartiumTools
//
//  System metrics for the Monitor tool (handoff v0.3). `LiveMetricsProvider`
//  reads real values through public APIs; any metric it cannot read comes
//  from `SimulatedMetricsProvider` and is shown with a `SIM` badge.
//  App-only: excluded from SmartiumWidgetsExtension.
//

import Darwin
import Foundation
#if os(iOS)
import UIKit
#elseif os(macOS)
import IOKit.ps
#endif

// MARK: - Readings

/// Per-core usage, 0–1, in kernel order.
struct StCPUReading {
  var cores: [Double]

  var total: Double {
    cores.isEmpty ? 0 : cores.reduce(0, +) / Double(cores.count)
  }
}

/// Used and total bytes.
struct StCapacityReading {
  var used: Double
  var total: Double

  var fraction: Double {
    total > 0 ? min(max(used / total, 0), 1) : 0
  }
}

struct StBatteryReading {
  /// 0–1.
  var level: Double
  var isCharging: Bool
}

/// Bytes per second.
struct StNetworkReading {
  var download: Double
  var upload: Double
}

// MARK: - Provider

/// One source of system metrics. A metric the provider cannot read returns nil.
protocol StMetricsProvider: AnyObject {
  func cpu() -> StCPUReading?
  func memory() -> StCapacityReading?
  func disk() -> StCapacityReading?
  /// GPU usage, 0–1.
  func gpu() -> Double?
  func battery() -> StBatteryReading?
  func network() -> StNetworkReading?
  func thermal() -> ProcessInfo.ThermalState?
}

// MARK: - Live

/// Real values from public APIs: Mach host statistics (CPU, memory), volume
/// capacity (disk), `getifaddrs` (network), UIDevice / IOKit power sources
/// (battery) and `ProcessInfo` (thermal). GPU has no public API, so it is nil.
final class LiveMetricsProvider: StMetricsProvider {
  private var previousTicks: [[UInt32]] = []
  private var previousInterfaces: [String: (download: UInt32, upload: UInt32)] = [:]
  private var previousNetworkDate: Date?

  init() {
#if os(iOS)
    UIDevice.current.isBatteryMonitoringEnabled = true
#endif
  }

  func cpu() -> StCPUReading? {
    var processorCount: natural_t = 0
    var info: processor_info_array_t?
    var infoCount: mach_msg_type_number_t = 0
    let result = host_processor_info(
      mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &processorCount, &info, &infoCount
    )
    guard result == KERN_SUCCESS, let info else { return nil }
    defer {
      vm_deallocate(
        mach_task_self_,
        vm_address_t(bitPattern: info),
        vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride)
      )
    }

    let states = Int(CPU_STATE_MAX)
    let ticks = (0..<Int(processorCount)).map { core in
      (0..<states).map { UInt32(bitPattern: info[core * states + $0]) }
    }
    // The first sample has no previous one: it shows usage since boot.
    let previous = previousTicks.count == ticks.count
      ? previousTicks
      : Array(repeating: Array(repeating: UInt32(0), count: states), count: ticks.count)
    previousTicks = ticks

    let cores = zip(ticks, previous).map { now, before in
      let delta = (0..<states).map { Double(now[$0] &- before[$0]) }
      let busy = delta[Int(CPU_STATE_USER)] + delta[Int(CPU_STATE_SYSTEM)] + delta[Int(CPU_STATE_NICE)]
      let total = busy + delta[Int(CPU_STATE_IDLE)]
      return total > 0 ? min(max(busy / total, 0), 1) : 0
    }
    return StCPUReading(cores: cores)
  }

  func memory() -> StCapacityReading? {
    var stats = vm_statistics64()
    var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &stats) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
      }
    }
    guard result == KERN_SUCCESS else { return nil }

    var pageSize: vm_size_t = 0
    host_page_size(mach_host_self(), &pageSize)
    // Like Activity Monitor's "Memory Used": active + wired + compressed.
    let pages = UInt64(stats.active_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)
    return StCapacityReading(
      used: Double(pages) * Double(pageSize),
      total: Double(ProcessInfo.processInfo.physicalMemory)
    )
  }

  func disk() -> StCapacityReading? {
    let url = URL(fileURLWithPath: NSHomeDirectory())
    guard let values = try? url.resourceValues(forKeys: [
      .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey
    ]),
      let total = values.volumeTotalCapacity,
      let available = values.volumeAvailableCapacityForImportantUsage
    else { return nil }
    return StCapacityReading(used: Double(total) - Double(available), total: Double(total))
  }

  func gpu() -> Double? {
    nil
  }

  func battery() -> StBatteryReading? {
#if os(iOS)
    let device = UIDevice.current
    guard device.batteryLevel >= 0 else { return nil }
    return StBatteryReading(
      level: Double(device.batteryLevel),
      isCharging: device.batteryState == .charging || device.batteryState == .full
    )
#elseif os(macOS)
    guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
          let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
    else { return nil }
    for source in sources {
      guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
            description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
            let current = description[kIOPSCurrentCapacityKey] as? Int,
            let maximum = description[kIOPSMaxCapacityKey] as? Int,
            maximum > 0
      else { continue }
      // Charging, or full on the charger (v0.11), like iOS's `.full`.
      let onCharger = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
      let isCharged = description[kIOPSIsChargedKey] as? Bool ?? false
      return StBatteryReading(
        level: Double(current) / Double(maximum),
        isCharging: (description[kIOPSIsChargingKey] as? Bool ?? false) || (onCharger && isCharged)
      )
    }
    return nil
#else
    return nil
#endif
  }

  func network() -> StNetworkReading? {
    var addresses: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&addresses) == 0, let first = addresses else { return nil }
    defer { freeifaddrs(addresses) }

    var interfaces: [String: (download: UInt32, upload: UInt32)] = [:]
    for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
      let entry = pointer.pointee
      guard let address = entry.ifa_addr,
            address.pointee.sa_family == UInt8(AF_LINK),
            let data = entry.ifa_data
      else { continue }
      let name = String(cString: entry.ifa_name)
      // Wi-Fi / Ethernet and cellular. Loopback, VPN tunnels and AWDL are left out.
      guard name.hasPrefix("en") || name.hasPrefix("pdp_ip") else { continue }
      let counters = data.assumingMemoryBound(to: if_data.self).pointee
      interfaces[name] = (counters.ifi_ibytes, counters.ifi_obytes)
    }

    let now = Date.now
    defer {
      previousInterfaces = interfaces
      previousNetworkDate = now
    }
    guard let previousDate = previousNetworkDate else {
      return StNetworkReading(download: 0, upload: 0)
    }
    let elapsed = now.timeIntervalSince(previousDate)
    guard elapsed > 0 else { return StNetworkReading(download: 0, upload: 0) }

    var download: UInt64 = 0
    var upload: UInt64 = 0
    for (name, counters) in interfaces {
      guard let before = previousInterfaces[name] else { continue }
      // 32-bit counters wrap around; `&-` gives the right delta across a wrap.
      download += UInt64(counters.download &- before.download)
      upload += UInt64(counters.upload &- before.upload)
    }
    return StNetworkReading(download: Double(download) / elapsed, upload: Double(upload) / elapsed)
  }

  func thermal() -> ProcessInfo.ThermalState? {
    ProcessInfo.processInfo.thermalState
  }
}

// MARK: - Simulated

/// Plausible random-walk values, like the v0.3 prototype. Used per metric
/// wherever the live provider returns nil.
final class SimulatedMetricsProvider: StMetricsProvider {
  private var cores: [Double]
  private var memoryLevel = 0.58
  private var gpuLevel = 0.34
  private var batteryLevel = 0.76
  private var download = 12.4e6
  private var upload = 0.8e6
  private var thermalLevel = 0

  /// iPhone layout: 2 performance + 4 efficiency cores.
  init(coreCount: Int = 6) {
    cores = (0..<coreCount).map { $0 < 2 ? 0.35 : 0.15 }
  }

  private func walk(_ value: Double, _ amount: Double, _ low: Double, _ high: Double) -> Double {
    min(high, max(low, value + (Double.random(in: 0..<1) - 0.5) * amount))
  }

  func cpu() -> StCPUReading? {
    let spike = Double.random(in: 0..<1) < 0.12
    cores = cores.enumerated().map { index, value in
      let performance = index < 2
      if spike && index < 3 { return Double.random(in: 0.8...1) }
      return walk(value * 0.85 + (performance ? 0.08 : 0.04), performance ? 0.5 : 0.3, 0.02, 1)
    }
    return StCPUReading(cores: cores)
  }

  func memory() -> StCapacityReading? {
    memoryLevel = walk(memoryLevel, 0.04, 0.35, 0.95)
    let total = 8 * 1_073_741_824.0
    return StCapacityReading(used: memoryLevel * total, total: total)
  }

  func disk() -> StCapacityReading? {
    StCapacityReading(used: 0.71 * 512e9, total: 512e9)
  }

  func gpu() -> Double? {
    gpuLevel = walk(gpuLevel, 0.22, 0.03, 0.98)
    return gpuLevel
  }

  func battery() -> StBatteryReading? {
    batteryLevel = max(0.05, batteryLevel - 0.0006)
    return StBatteryReading(level: batteryLevel, isCharging: false)
  }

  func network() -> StNetworkReading? {
    download = walk(download, 6e6, 0, 40e6)
    upload = walk(upload, 0.7e6, 0, 4e6)
    return StNetworkReading(download: download, upload: upload)
  }

  func thermal() -> ProcessInfo.ThermalState? {
    if Double.random(in: 0..<1) < 0.05 {
      thermalLevel = min(3, max(0, thermalLevel + (Double.random(in: 0..<1) < 0.55 ? -1 : 1)))
    }
    return ProcessInfo.ThermalState(rawValue: thermalLevel) ?? .nominal
  }
}

// MARK: - Core names

nonisolated enum StCoreLayout {
  /// Performance and efficiency core counts from `hw.perflevel0/1.logicalcpu`.
  static func performanceLevels() -> (performance: Int, efficiency: Int)? {
    func value(_ name: String) -> Int? {
      var result: Int32 = 0
      var size = MemoryLayout<Int32>.size
      return sysctlbyname(name, &result, &size, nil, 0) == 0 ? Int(result) : nil
    }
    guard let performance = value("hw.perflevel0.logicalcpu") else { return nil }
    return (performance, value("hw.perflevel1.logicalcpu") ?? 0)
  }

  /// Row order and names for the heatmap: performance cores first (P1…), then
  /// efficiency (E1…). Assumes the kernel lists efficiency cores first, as on
  /// Apple silicon; with unknown counts every core is named C1….
  static func rows(coreCount: Int) -> [(name: String, index: Int)] {
    if let levels = performanceLevels(), levels.performance + levels.efficiency == coreCount {
      let efficiency = (0..<levels.efficiency).map { (name: "E\($0 + 1)", index: $0) }
      let performance = (0..<levels.performance).map { (name: "P\($0 + 1)", index: levels.efficiency + $0) }
      return performance + efficiency
    }
    return (0..<coreCount).map { (name: "C\($0 + 1)", index: $0) }
  }
}
