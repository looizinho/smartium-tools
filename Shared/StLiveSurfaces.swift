//
//  StLiveSurfaces.swift
//  SmartiumTools
//
//  App Group snapshots read by the Control Center controls and the Timer and
//  Monitor widgets (handoff v0.5). The app writes them; the widget extension
//  only reads them.
//  v0.12.1 §2: in `Shared/` so the watch app can mirror what the iPhone
//  sends into the watch's App Group, for the watch's own complications.
//

import AppIntents
import Foundation
import SwiftUI
#if canImport(WidgetKit)
import WidgetKit
#endif

nonisolated enum StLiveSurfaces {
    static let timerWidgetKind = "SmartiumTimerWidget"
    static let monitorWidgetKind = "SmartiumMonitorWidget"
    static let devicesWidgetKind = "SmartiumDevicesWidget"

    enum ControlKind {
        static let orb = "dev.smartium.tools.control.orb"
        static let voice = "dev.smartium.tools.control.voice"
        static let timer = "dev.smartium.tools.control.timer"
        static let staging = "dev.smartium.tools.control.staging"
        static let monitor = "dev.smartium.tools.control.monitor"
    }

    private enum Key {
        static let timer = "dev.smartium.tools.timerSnapshot"
        static let metrics = "dev.smartium.tools.metricsSnapshot"
        static let orbActivity = "dev.smartium.tools.orbActivityActive"
        static let pendingTool = "dev.smartium.tools.pendingTool"
        static let pinnedMetric = "dev.smartium.tools.pinnedMetric"
        static let devices = "dev.smartium.tools.devices"
    }

    /// Same as `ToolSharedState.appGroupIdentifier`, which the watch can't
    /// see (it lives with the Orb's state). Keep the two identical.
    static let appGroupIdentifier = "group.dev.smartium.tools"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }

    // MARK: Timer

    /// Read-only: writes go through `publishTimer(_:)`, so none of them
    /// can skip the reload (v0.12.1 §3).
    static var timer: StTimerSnapshot {
        read(Key.timer) ?? StTimerSnapshot()
    }

    /// Stores the timer and reloads the Timer widgets and control. Their
    /// timeline only changes on a reload, so a write without one left the
    /// placed widget frozen on its last state (v0.12.1 §3).
    static func publishTimer(_ snapshot: StTimerSnapshot) {
        write(snapshot, Key.timer)
        reloadTimer()
    }

    // MARK: Monitor

    static var metrics: StMetricsSnapshot? {
        get { read(Key.metrics) }
        set { write(newValue, Key.metrics) }
    }

    /// Stores the sample and reloads the Monitor widgets (the watch, which
    /// gets a new sample at most every 30 s).
    static func publishMetrics(_ snapshot: StMetricsSnapshot?) {
        guard snapshot != metrics else { return }
        metrics = snapshot
        reloadMonitor()
    }

    /// Metric pinned to the Monitor hero (`settings.monitor.pinnedMetric`, v0.6),
    /// mirrored here so the small widget can default to it.
    static var pinnedMetric: String? {
        defaults.string(forKey: Key.pinnedMetric)
    }

    /// Stores the pinned metric and reloads the Monitor widgets when it changed.
    static func publishPinnedMetric(_ value: String?) {
        guard value != pinnedMetric else { return }
        defaults.set(value, forKey: Key.pinnedMetric)
        reloadMonitor()
    }

    /// Widget metric for the pinned one. Nothing pinned means CPU, like the
    /// hero. Battery has a widget ring since v0.12.
    static var pinnedWidgetMetric: StWidgetMetric {
        switch pinnedMetric {
        case "memory": .memory
        case "disk": .disk
        case "gpu": .gpu
        case "battery": .battery
        default: .cpu
        }
    }

    // MARK: Devices

    /// Every device's battery as the app last saw it (v0.12 §3.2), already
    /// ordered (`StDeviceList.ordered`, this device first).
    static var devices: [StDeviceBattery] {
        get { read(Key.devices) ?? [] }
        set { write(newValue, Key.devices) }
    }

    /// Stores the list and reloads the Dispositivos widgets when it changed.
    static func publishDevices(_ list: [StDeviceBattery]) {
        guard list != devices else { return }
        devices = list
        reloadDevices()
    }

    // MARK: Orb

    /// Whether the Orb's Live Activity is running, as last seen by the app.
    static var isOrbActivityActive: Bool {
        get { defaults.bool(forKey: Key.orbActivity) }
        set { defaults.set(newValue, forKey: Key.orbActivity) }
    }

    // MARK: Navigation

    /// Tab an intent asked the app to open; the app consumes it on activation.
    static func requestTool(_ destination: StToolDestination) {
        defaults.set(destination.rawValue, forKey: Key.pendingTool)
    }

    static func takePendingTool() -> StToolDestination? {
        guard let raw = defaults.string(forKey: Key.pendingTool) else { return nil }
        defaults.removeObject(forKey: Key.pendingTool)
        return StToolDestination(rawValue: raw)
    }

    // MARK: Reload

    static func reloadTimer() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: timerWidgetKind)
        reloadControl(ControlKind.timer)
        #endif
    }

    static func reloadMonitor() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: monitorWidgetKind)
        reloadControl(ControlKind.monitor)
        #endif
    }

    static func reloadDevices() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: devicesWidgetKind)
        #endif
    }

    static func reloadControl(_ kind: String) {
        #if canImport(WidgetKit) && os(iOS)
        ControlCenter.shared.reloadControls(ofKind: kind)
        #endif
    }

    private static func read<Value: Decodable>(_ key: String) -> Value? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(Value.self, from: $0) }
    }

    private static func write<Value: Encodable>(_ value: Value?, _ key: String) {
        guard let value, let data = try? JSONEncoder().encode(value) else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(data, forKey: key)
    }
}

extension Notification.Name {
    /// Posted in the app process after an intent asks for a tab.
    static let smartiumOpenToolRequested = Notification.Name("dev.smartium.tools.openToolRequested")
}

// The snapshot types and `StToolDestination` live in `Shared/StSharedSnapshots.swift`
// (v0.10), so the watch app can decode them too.
