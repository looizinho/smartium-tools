//
//  StTimerSync.swift
//  SmartiumTools
//
//  One timer for iPhone, Watch and Mac (handoff v0.12 §1). The timer goes
//  to the iCloud key-value store under `timer.state`, in an envelope with
//  the writer's device id and clock. A device writes only when the user acts
//  (start, pause, resume, ±time, reset) and when the timer reaches its end;
//  never once a second, since the `fireDate` is enough. It reads on
//  `didChangeExternallyNotification` and on opening, through `StDeviceSync`,
//  which already handles the account, the quota and the first sync.
//
//  Adopting a newer envelope reschedules the local timer (AlarmKit on the
//  iPhone, `StMacTimerService` on the Mac) and never writes back (§1.3).
//  The watch keeps mirroring the iPhone through WatchConnectivity.
//
//  App-only (iOS and macOS): the whole file is under `#if SMARTIUM_APP`.
//

#if SMARTIUM_APP
import Foundation
import OSLog
#if os(macOS)
import AppKit
#endif

/// The timer as one device last wrote it (§1.2).
nonisolated struct StTimerEnvelope: Codable, Sendable, Equatable {
    var snapshot: StTimerSnapshot
    /// Id of the device that wrote it (`StDeviceIdentity`, as in v0.11).
    var originID: String
    /// The writer's clock.
    var updatedAt: Date

    /// Below this gap, two devices' writes are a tie (§1.2).
    static let tieInterval: TimeInterval = 2

    /// Whether this envelope replaces `other`: the newer one wins; within
    /// 2 s of a different device, the larger `originID` wins, so the two
    /// devices settle on the same one instead of swapping back and forth.
    func wins(over other: StTimerEnvelope?) -> Bool {
        guard let other else { return true }
        let gap = updatedAt.timeIntervalSince(other.updatedAt)
        if originID != other.originID, abs(gap) < Self.tieInterval {
            return originID > other.originID
        }
        return gap > 0
    }
}

@MainActor
final class StTimerSync {
    static let shared = StTimerSync()

    static let key = "timer.state"
    /// Local copy of the newest envelope known here, in the app's own defaults.
    private static let lastKey = "timerEnvelope"
    /// After an adoption, the local timer settles for a moment (AlarmKit
    /// cancels and schedules again); what it reports then isn't the user's.
    private static let settleInterval: TimeInterval = 3

    private let thisID = StDeviceIdentity.id
    /// The newest envelope this device wrote or adopted.
    private var latest: StTimerEnvelope? {
        didSet { Self.store(latest) }
    }
    private var adoptedAt: Date?
    private let logger = Logger(subsystem: "dev.smartium.tools", category: "timerSync")

    private init() {
        latest = Self.stored()
#if os(macOS)
        // §1.3: a Mac waking up reads the store before trusting its counter.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                NSUbiquitousKeyValueStore.default.synchronize()
                StTimerSync.shared.reload()
            }
        }
#endif
    }

    /// An adoption happened a moment ago: local changes are its echo.
    var isSettling: Bool {
        adoptedAt.map { Date.now.timeIntervalSince($0) < Self.settleInterval } ?? false
    }

    // MARK: Writing

    /// A user action or the end, on this device: sends the timer to the
    /// others. Without iCloud (or over quota) the timer stays local.
    func publish(_ snapshot: StTimerSnapshot) {
        let envelope = StTimerEnvelope(snapshot: snapshot, originID: thisID, updatedAt: .now)
        latest = envelope
        let sync = StDeviceSync.shared
        guard sync.hasICloud, !sync.quotaExceeded,
              let data = try? JSONEncoder().encode(envelope) else { return }
        StKeyValueWriter.shared.write(data, forKey: Self.key)
    }

    // MARK: Reading

    /// Reads `timer.state` and adopts it when another device wrote something
    /// newer. Called by `StDeviceSync` on opening and on every external change.
    func reload() {
        guard StDeviceSync.shared.hasICloud,
              let data = NSUbiquitousKeyValueStore.default.data(forKey: Self.key),
              let envelope = try? JSONDecoder().decode(StTimerEnvelope.self, from: data),
              envelope.originID != thisID,
              envelope != latest,
              envelope.wins(over: latest)
        else { return }
        latest = envelope
        adoptedAt = .now
        logger.info("Timer adotado de outro aparelho: \(envelope.snapshot.phase.rawValue, privacy: .public)")
        adopt(envelope.snapshot)
    }

    private func adopt(_ remote: StTimerSnapshot) {
        var snapshot = remote
        // §1.3: a countdown whose end already passed has finished; it is
        // adopted as the end, which never rings again.
        if snapshot.phase == .running, (snapshot.fireDate ?? .distantPast) <= .now {
            snapshot.phase = .alerting
            snapshot.fireDate = nil
        }
#if os(iOS) && canImport(AlarmKit)
        Task { await StTimerService.adopt(snapshot) }
#elseif os(macOS)
        StMacTimerService.shared.adopt(snapshot)
#endif
    }

    // MARK: Local copy

    private static func stored() -> StTimerEnvelope? {
        UserDefaults.standard.data(forKey: lastKey)
            .flatMap { try? JSONDecoder().decode(StTimerEnvelope.self, from: $0) }
    }

    private static func store(_ envelope: StTimerEnvelope?) {
        let data = envelope.flatMap { try? JSONEncoder().encode($0) }
        UserDefaults.standard.set(data, forKey: lastKey)
    }
}
#endif
