//
//  StDeviceSync.swift
//  SmartiumTools
//
//  Device batteries, synced (handoff v0.11 §1.2–1.3). Reads this device's
//  battery, publishes it to the iCloud key-value store under
//  `battery.<id>` and reads the other devices' entries. On iPhone it also
//  takes the watch's entry from WatchConnectivity, publishes it for the Mac
//  and sends the whole list back to the watch. Kept apart from the
//  iCloud Drive `settings.json`. Since v0.12 it also hands the timer's
//  key (`timer.state`) to `StTimerSync`, publishes the list to the App Group
//  for the Dispositivos widget and, on iPhone, feeds the battery Live Activity.
//
//  App-only (iOS and macOS): the whole file is under `#if SMARTIUM_APP`.
//

#if SMARTIUM_APP
import Foundation
import Observation
import OSLog
#if os(iOS)
import UIKit
#elseif os(macOS)
import IOKit
import IOKit.ps
#endif

@Observable
final class StDeviceSync {
    static let shared = StDeviceSync()

    /// Warning row at the end of the Dispositivos card; one at a time.
    enum Notice: Equatable {
        /// No iCloud account: only this device (and, on iPhone, the watch).
        case noICloud
        /// A write was refused for quota: this device's battery isn't sent.
        case syncUnavailable
    }

    /// Writes per device: at most one a minute, except a charging change.
    static let writeInterval: TimeInterval = 60
    static let keyPrefix = "battery."

    let thisID = StDeviceIdentity.id
    private(set) var this: StDeviceBattery
    /// Entries read from the key-value store, by id (never this device).
    private(set) var cloud: [String: StDeviceBattery] = [:]
    /// Watch entries received through WatchConnectivity (iPhone), by id.
    private(set) var watches: [String: StDeviceBattery] = [:]
    private(set) var hasICloud = FileManager.default.ubiquityIdentityToken != nil
    /// Set by a quota refusal; writing stops until the next launch.
    private(set) var quotaExceeded = false

    @ObservationIgnored private let provider = LiveMetricsProvider()
    @ObservationIgnored private var isObserving = false
    @ObservationIgnored private var identityToken: (any NSObjectProtocol & NSCopying & NSCoding)?
    @ObservationIgnored private var lastWritten: [String: StDeviceBattery] = [:]
    @ObservationIgnored private var lastWriteDate: [String: Date] = [:]
    @ObservationIgnored private var pendingWrites: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private let logger = Logger(subsystem: "dev.smartium.tools", category: "battery")

    private init() {
        this = StDeviceBattery(
            id: thisID,
            kind: Self.kind,
            name: Self.deviceName(hasBattery: true),
            level: nil,
            isCharging: false,
            updatedAt: .now
        )
        identityToken = FileManager.default.ubiquityIdentityToken
        this = reading()
    }

    /// Every device, this one first (§1.4 order). Without iCloud: this device
    /// and the watches that came through WatchConnectivity.
    var devices: [StDeviceBattery] {
        var byID = hasICloud ? cloud : [:]
        for (id, watch) in watches where (byID[id]?.updatedAt ?? .distantPast) <= watch.updatedAt {
            byID[id] = watch
        }
        byID[thisID] = this
        return StDeviceList.ordered(Array(byID.values), thisID: thisID)
    }

    /// "Sem iCloud" wins over "Sincronização indisponível".
    var notice: Notice? {
        if !hasICloud { return .noICloud }
        if quotaExceeded { return .syncUnavailable }
        return nil
    }

    // MARK: Lifecycle

    /// On launch and every time the app becomes active: starts observing,
    /// syncs the key-value store, reads every entry and publishes this one.
    func activate() {
        startObserving()
        checkAccount()
        if hasICloud {
            NSUbiquitousKeyValueStore.default.synchronize()
            reloadCloud()
            StTimerSync.shared.reload()
        }
        refreshLocal(isOpening: true)
        publishSurfaces()
#if os(iOS) && canImport(ActivityKit)
        // The first list is the baseline for "started charging" (v0.12 §3.3).
        StBatteryActivityManager.shared.devicesChanged(devices)
#endif
    }

    /// The Hero's refresh button (v0.12 §1.5): reads this device's battery
    /// and publishes it at once, then reads the other devices again.
    func refreshNow() {
        checkAccount()
        let new = reading()
        let changed = new != this
        this = new
        if hasICloud, !quotaExceeded {
            pendingWrites[thisID]?.cancel()
            pendingWrites[thisID] = nil
            write(this)
            NSUbiquitousKeyValueStore.default.synchronize()
            reloadCloud()
        }
        if changed { devicesChanged() }
    }

    private func startObserving() {
        guard !isObserving else { return }
        isObserving = true
        let center = NotificationCenter.default

        center.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default,
            queue: .main
        ) { notification in
            let reason = notification.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int
            MainActor.assumeIsolated { StDeviceSync.shared.cloudChanged(reason: reason) }
        }
        center.addObserver(forName: .NSUbiquityIdentityDidChange, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { StDeviceSync.shared.checkAccount(force: true) }
        }

#if os(iOS)
        // `LiveMetricsProvider` turned battery monitoring on.
        for name in [UIDevice.batteryLevelDidChangeNotification, UIDevice.batteryStateDidChangeNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { StDeviceSync.shared.refreshLocal() }
            }
        }
#elseif os(macOS)
        let source = IOPSNotificationCreateRunLoopSource({ _ in
            Task { @MainActor in StDeviceSync.shared.refreshLocal() }
        }, nil)?.takeRetainedValue()
        if let source {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        }
#endif
    }

    // MARK: Local reading

    private static var kind: StDeviceBattery.Kind {
#if os(macOS)
        .mac
#else
        .iphone
#endif
    }

    private func reading() -> StDeviceBattery {
        let battery = provider.battery()
        return StDeviceBattery(
            id: thisID,
            kind: Self.kind,
            name: Self.deviceName(hasBattery: battery != nil),
            level: battery?.level,
            isCharging: battery?.isCharging ?? false,
            updatedAt: .now
        )
    }

    /// Reads the battery again and publishes it when it changed enough.
    func refreshLocal(isOpening: Bool = false) {
        let new = reading()
        let changed = new.level != this.level || new.isCharging != this.isCharging || new.name != this.name
        if changed || isOpening { this = new }
        publish(this, isOpening: isOpening)
        if changed { devicesChanged() }
    }

    // MARK: Watch (iPhone)

    /// The watch's own entry, from WatchConnectivity.
    func receiveWatch(_ entry: StDeviceBattery) {
        guard entry.id != thisID, entry.kind == .watch else { return }
        if let known = watches[entry.id], known.updatedAt > entry.updatedAt { return }
        guard watches[entry.id] != entry else { return }
        watches[entry.id] = entry
        publish(entry, isOpening: false)
        devicesChanged()
    }

    private func devicesChanged() {
        let devices = devices
#if os(iOS)
        StWatchSync.shared.devicesChanged(devices)
#if canImport(ActivityKit)
        StBatteryActivityManager.shared.devicesChanged(devices)
#endif
#endif
        publishSurfaces(devices)
    }

    /// The list for the Dispositivos widget (v0.12 §3.2): the extension
    /// can't read the key-value store, so the app copies it to the App Group.
    private func publishSurfaces(_ devices: [StDeviceBattery]? = nil) {
        StLiveSurfaces.publishDevices(devices ?? self.devices)
    }

    // MARK: Key-value store

    private func cloudChanged(reason: Int?) {
        switch reason {
        case NSUbiquitousKeyValueStoreQuotaViolationChange:
            logger.error("Cota do iCloud key-value store excedida; a bateria deixa de ser enviada.")
            quotaExceeded = true
            pendingWrites.values.forEach { $0.cancel() }
            pendingWrites = [:]
            reloadCloud()
        case NSUbiquitousKeyValueStoreAccountChange:
            checkAccount(force: true)
        default:
            // Server change and the first sync (`InitialSyncChange`) alike.
            reloadCloud()
            StTimerSync.shared.reload()
        }
    }

    /// Re-checks the iCloud account. A different (or no) account drops the
    /// other devices and reads everything again.
    private func checkAccount(force: Bool = false) {
        let token = FileManager.default.ubiquityIdentityToken
        let tokenChanged = !Self.same(token, identityToken)
        identityToken = token
        hasICloud = token != nil
        guard force || tokenChanged else { return }
        cloud = [:]
        lastWritten = [:]
        lastWriteDate = [:]
        if hasICloud {
            NSUbiquitousKeyValueStore.default.synchronize()
            reloadCloud()
            StTimerSync.shared.reload()
            publish(this, isOpening: true)
            watches.values.forEach { publish($0, isOpening: true) }
        }
        devicesChanged()
    }

    private static func same(_ lhs: (any NSObjectProtocol & NSCopying & NSCoding)?, _ rhs: (any NSObjectProtocol & NSCopying & NSCoding)?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): true
        case let (lhs?, rhs?): lhs.isEqual(rhs)
        default: false
        }
    }

    /// Reads every `battery.*` key.
    private func reloadCloud() {
        guard hasICloud else {
            cloud = [:]
            return
        }
        let store = NSUbiquitousKeyValueStore.default
        let decoder = JSONDecoder()
        var entries: [String: StDeviceBattery] = [:]
        for (key, value) in store.dictionaryRepresentation where key.hasPrefix(Self.keyPrefix) {
            guard let data = value as? Data,
                  let entry = try? decoder.decode(StDeviceBattery.self, from: data),
                  entry.id != thisID,
                  Date.now.timeIntervalSince(entry.updatedAt) <= StDeviceBattery.maxAge
            else { continue }
            entries[entry.id] = entry
        }
        guard entries != cloud else { return }
        cloud = entries
        devicesChanged()
    }

    /// Writes an entry when it is new, moved a whole point or changed
    /// charging. At most once a minute per device; a charging change goes at
    /// once.
    private func publish(_ entry: StDeviceBattery, isOpening: Bool) {
        guard hasICloud, !quotaExceeded else { return }
        let last = lastWritten[entry.id]
        let chargingChanged = last.map { $0.isCharging != entry.isCharging } ?? true
        let levelChanged = last.map { $0.percent != entry.percent || $0.name != entry.name } ?? true
        guard isOpening || chargingChanged || levelChanged else { return }

        let elapsed = lastWriteDate[entry.id].map { Date.now.timeIntervalSince($0) } ?? .infinity
        pendingWrites[entry.id]?.cancel()
        if chargingChanged || elapsed >= Self.writeInterval {
            pendingWrites[entry.id] = nil
            write(entry)
            return
        }
        let id = entry.id
        pendingWrites[id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.writeInterval - elapsed))
            guard !Task.isCancelled, let self else { return }
            self.pendingWrites[id] = nil
            // The latest reading, not the one that was scheduled.
            let latest = id == self.thisID ? self.this : (self.watches[id] ?? entry)
            self.write(latest)
        }
    }

    private func write(_ entry: StDeviceBattery) {
        guard hasICloud, !quotaExceeded, let data = try? JSONEncoder().encode(entry) else { return }
        lastWritten[entry.id] = entry
        lastWriteDate[entry.id] = .now
        StKeyValueWriter.shared.write(data, forKey: Self.keyPrefix + entry.id)
    }

    // MARK: Names

    /// "iPhone" (or "iPad"), or the Mac's model name ("MacBook Pro").
    /// `UIDevice.name` only gives a generic name, so the type is used (§1.1).
    private static func deviceName(hasBattery: Bool) -> String {
#if os(iOS)
        UIDevice.current.model
#elseif os(macOS)
        macModelName ?? (hasBattery ? "MacBook" : "Mac")
#else
        "iPhone"
#endif
    }

#if os(macOS)
    /// "MacBook Pro" from the device tree's `product-name`
    /// ("MacBook Pro (14-inch, M3, 2023)"), else from `hw.model`.
    private static let macModelName: String? = {
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/product")
        if entry != 0 {
            defer { IOObjectRelease(entry) }
            if let data = IORegistryEntryCreateCFProperty(entry, "product-name" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? Data {
                let full = String(decoding: data.prefix { $0 != 0 }, as: UTF8.self)
                let name = full.components(separatedBy: " (").first?.trimmingCharacters(in: .whitespaces) ?? ""
                if !name.isEmpty { return name }
            }
        }
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &buffer, &size, nil, 0)
        let model = String(cString: buffer)
        let names: [(String, String)] = [
            ("MacBookPro", "MacBook Pro"), ("MacBookAir", "MacBook Air"), ("MacBook", "MacBook"),
            ("Macmini", "Mac mini"), ("iMac", "iMac"), ("MacPro", "Mac Pro")
        ]
        return names.first { model.hasPrefix($0.0) }?.1
    }()
#endif
}

/// Writes to the key-value store off the main thread, in order (batteries
/// and, since v0.12, the timer).
nonisolated final class StKeyValueWriter: Sendable {
    static let shared = StKeyValueWriter()

    private let queue = DispatchQueue(label: "dev.smartium.tools.keyValueSync", qos: .utility)

    func write(_ data: Data, forKey key: String) {
        queue.async {
            NSUbiquitousKeyValueStore.default.set(data, forKey: key)
        }
    }
}
#endif
