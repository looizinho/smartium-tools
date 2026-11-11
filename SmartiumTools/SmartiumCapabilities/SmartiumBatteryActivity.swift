//
//  SmartiumBatteryActivity.swift
//  SmartiumTools
//
//  The devices' batteries in a Live Activity (handoff v0.12 §3.3): the
//  attributes and the stop intent, shared with the widget extension, and
//  the app's manager. Always started by the iPhone: when a device starts
//  charging, or from the button on the Monitor's Dispositivos card. Ends
//  when nothing has charged for 2 min (if it started on its own), when the
//  user ends it, or after 8 h.
//

import AppIntents
import Foundation

#if canImport(ActivityKit) && os(iOS)
import ActivityKit

nonisolated struct StBatteryActivityAttributes: ActivityAttributes, Sendable {
    nonisolated struct ContentState: Codable, Hashable, Sendable {
        /// Already ordered (`StDeviceList.ordered`).
        var devices: [StDeviceBattery]
        /// The device whose battery changed last (compact view's icon).
        var changedKind: StDeviceBattery.Kind?
        var updatedAt: Date

        /// One device per kind: iPhone, Apple Watch, Mac.
        var ringDevices: [StDeviceBattery] {
            StDeviceList.ringDevices(devices)
        }

        /// Minimal view: the device with the lowest charge.
        var lowest: StDeviceBattery? {
            ringDevices.min { ($0.level ?? 2) < ($1.level ?? 2) }
        }

        /// Compact view's icon: the device that changed, else the first.
        var changed: StDeviceBattery? {
            ringDevices.first { $0.kind == changedKind } ?? ringDevices.first
        }
    }

    var startedAt: Date
}

/// Ends the battery Live Activity from the expanded island or the Lock Screen.
struct StopBatteryActivityIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Encerrar baterias ao vivo"
    static let description = IntentDescription("Encerra a Atividade ao Vivo das baterias.")
    static let isDiscoverable = false

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        #if SMARTIUM_APP
        await StBatteryActivityManager.shared.stop()
        #endif
        return .result()
    }
}

#if SMARTIUM_APP
import Observation

@MainActor
@Observable
final class StBatteryActivityManager {
    static let shared = StBatteryActivityManager()

    /// Nothing charging for this long ends an activity that started on its own.
    static let idleEnd: TimeInterval = 120
    /// The system's limit too.
    static let maxDuration: TimeInterval = 8 * 3_600

    private(set) var isRunning = false
    private(set) var lastErrorMessage: String?

    /// Charging devices at the last change; nil until the first list.
    @ObservationIgnored private var charging: Set<String>?
    @ObservationIgnored private var last: [StDeviceBattery] = []
    @ObservationIgnored private var changedKind: StDeviceBattery.Kind?
    @ObservationIgnored private var startedOnItsOwn = false
    @ObservationIgnored private var idleEndTask: Task<Void, Never>?

    private init() {
        isRunning = activity != nil
    }

    private var activity: Activity<StBatteryActivityAttributes>? {
        Activity<StBatteryActivityAttributes>.activities.first {
            $0.activityState == .active || $0.activityState == .stale
        }
    }

    // MARK: Changes

    /// Every change of the device list (`StDeviceSync`).
    func devicesChanged(_ devices: [StDeviceBattery]) {
        let nowCharging = Set(devices.filter { $0.isCharging && $0.level != nil }.map(\.id))
        let startedCharging = charging.map { !nowCharging.subtracting($0).isEmpty } ?? false
        charging = nowCharging
        if let kind = Self.changedKind(from: last, to: devices) { changedKind = kind }
        last = devices
        isRunning = activity != nil

        if !isRunning {
            if startedCharging {
                Task { await start(devices: devices, onItsOwn: true) }
            }
            return
        }
        if let activity, Date.now.timeIntervalSince(activity.attributes.startedAt) >= Self.maxDuration {
            Task { await stop() }
            return
        }
        Task { await update(devices) }
        scheduleIdleEnd(isCharging: !nowCharging.isEmpty)
    }

    /// The device whose level or charging changed.
    private static func changedKind(from old: [StDeviceBattery], to new: [StDeviceBattery]) -> StDeviceBattery.Kind? {
        let byID = Dictionary(old.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return new.first { device in
            guard let previous = byID[device.id] else { return false }
            return previous.percent != device.percent || previous.isCharging != device.isCharging
        }?.kind
    }

    // MARK: Start, update, end

    /// The Dispositivos card's button.
    func toggle() async {
        if activity != nil {
            await stop()
        } else {
            await start(devices: StDeviceSync.shared.devices, onItsOwn: false)
        }
    }

    private func start(devices: [StDeviceBattery], onItsOwn: Bool) async {
        lastErrorMessage = nil
        guard activity == nil else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            lastErrorMessage = "As Atividades ao Vivo estão desativadas nos Ajustes."
            return
        }
        let now = Date.now
        let state = StBatteryActivityAttributes.ContentState(devices: devices, changedKind: changedKind, updatedAt: now)
        do {
            _ = try Activity.request(
                attributes: StBatteryActivityAttributes(startedAt: now),
                content: .init(state: state, staleDate: now.addingTimeInterval(Self.maxDuration)),
                pushType: nil
            )
            startedOnItsOwn = onItsOwn
            isRunning = true
            scheduleIdleEnd(isCharging: devices.contains { $0.isCharging && $0.level != nil })
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func update(_ devices: [StDeviceBattery]) async {
        guard let activity else { return }
        let state = StBatteryActivityAttributes.ContentState(devices: devices, changedKind: changedKind, updatedAt: .now)
        guard state.devices != activity.content.state.devices else { return }
        let staleDate = activity.attributes.startedAt.addingTimeInterval(Self.maxDuration)
        await activity.update(ActivityContent(state: state, staleDate: staleDate))
    }

    func stop() async {
        idleEndTask?.cancel()
        idleEndTask = nil
        for activity in Activity<StBatteryActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        isRunning = false
    }

    /// 2 min with nothing charging ends an activity that started on its own;
    /// one the user started ends by the user or after 8 h.
    private func scheduleIdleEnd(isCharging: Bool) {
        guard startedOnItsOwn, !isCharging else {
            idleEndTask?.cancel()
            idleEndTask = nil
            return
        }
        guard idleEndTask == nil else { return }
        idleEndTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.idleEnd))
            guard !Task.isCancelled, let self else { return }
            self.idleEndTask = nil
            await self.stop()
        }
    }
}
#endif
#endif
