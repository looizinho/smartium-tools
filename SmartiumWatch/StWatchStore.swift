//
//  StWatchStore.swift
//  SmartiumWatch
//
//  Watch side of the bridge (handoff v0.10 §3): receives `StWatchState` from
//  the iPhone, keeps the last one on disk so the app opens with it even
//  without a connection, and says when the data is stale. Since v0.11 it
//  also reads the watch's own battery and sends it to the iPhone.
//

import Foundation
import Observation
import OSLog
@preconcurrency import WatchConnectivity
import WatchKit

@Observable
final class StWatchStore {
    static let shared = StWatchStore()

    /// Voz and Monitor count as disconnected once their data is this old.
    static let staleAfter: TimeInterval = 10

    private(set) var state: StWatchState
    /// When the last state arrived on this watch (local clock).
    private(set) var receivedAt: Date?
    private(set) var isReachable = false
    /// Bumped for each new focus, so the page switches and the tag glows.
    private(set) var focusEvent: FocusEvent?
    /// This watch's battery (v0.11), read locally.
    private(set) var battery: StDeviceBattery

    /// This watch first, then the devices the iPhone knows (v0.11).
    var devices: [StDeviceBattery] {
        StDeviceList.ordered(StDeviceList.merging(battery, into: state.devices ?? []), thisID: battery.id)
    }

    struct FocusEvent: Equatable {
        let tool: StToolDestination
        let id: Date
    }

    @ObservationIgnored private let link = StWatchSessionLink()
    @ObservationIgnored private let cacheURL: URL?
    @ObservationIgnored private let logger = Logger(subsystem: "dev.smartium.tools.watch", category: "sync")
    @ObservationIgnored private var lastSentBattery: StDeviceBattery?
    @ObservationIgnored private var lastBatterySend: Date?
    @ObservationIgnored private var batteryTask: Task<Void, Never>?
    @ObservationIgnored private var lastHandledFocus: Date? {
        get { UserDefaults.standard.object(forKey: "lastHandledFocus") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "lastHandledFocus") }
    }

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        cacheURL = base?.appendingPathComponent("watch-state.json")
        let cached = cacheURL.flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode(Cached.self, from: $0) }
        state = cached?.state ?? StWatchState()
        battery = Self.readBattery()
        receivedAt = cached?.receivedAt
        // Focus from before this launch is already old news.
        lastHandledFocus = max(lastHandledFocus ?? .distantPast, state.focus?.at ?? .distantPast)

        link.onState = { [weak self] state in self?.receive(state) }
        link.onReachability = { [weak self] reachable in self?.reachabilityChanged(reachable) }
    }

    /// Activates the session and asks the iPhone for its current state.
    func activate() {
        link.activate()
        sayHello()
    }

    /// On opening or becoming active: the iPhone answers with its state, and
    /// gets this watch's battery.
    func sayHello() {
        link.sayHello()
        refreshBattery(isOpening: true)
    }

    // MARK: Battery (v0.11)

    /// Sends per minute at most, except a charging change.
    static let batteryInterval: TimeInterval = 60

    private static let batteryID = StDeviceIdentity.id

    private static func readBattery() -> StDeviceBattery {
        let device = WKInterfaceDevice.current()
        device.isBatteryMonitoringEnabled = true
        let level = device.batteryLevel
        let state = device.batteryState
        return StDeviceBattery(
            id: batteryID,
            kind: .watch,
            name: "Apple Watch",
            level: level >= 0 ? Double(level) : nil,
            isCharging: state == .charging || state == .full,
            updatedAt: .now
        )
    }

    /// Reads the battery while the app runs (watchOS posts no battery
    /// notifications, so it is read every 20 s) and sends it when it is new,
    /// moved a whole point or changed charging.
    private func refreshBattery(isOpening: Bool) {
        battery = Self.readBattery()
        sendBatteryIfNeeded(isOpening: isOpening)
        guard batteryTask == nil else { return }
        batteryTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                guard let self else { return }
                self.battery = Self.readBattery()
                self.sendBatteryIfNeeded(isOpening: false)
            }
        }
    }

    private func sendBatteryIfNeeded(isOpening: Bool) {
        let last = lastSentBattery
        let chargingChanged = last.map { $0.isCharging != battery.isCharging } ?? true
        let levelChanged = last.map { $0.percent != battery.percent } ?? true
        guard isOpening || chargingChanged || levelChanged else { return }
        let elapsed = lastBatterySend.map { Date.now.timeIntervalSince($0) } ?? .infinity
        // A throttled change goes with the next 20 s read past the minute.
        guard chargingChanged || elapsed >= Self.batteryInterval else { return }
        lastSentBattery = battery
        lastBatterySend = .now
        link.sendBattery(battery)
    }

    /// No iPhone: the session can't reach it and the last data is old.
    func isDisconnected(at date: Date) -> Bool {
        guard !isReachable else { return false }
        guard let receivedAt else { return true }
        return date.timeIntervalSince(receivedAt) > Self.staleAfter
    }

    // MARK: Receiving

    private func receive(_ newState: StWatchState) {
        state = newState
        receivedAt = .now
        if let focus = newState.focus, focus.at > (lastHandledFocus ?? .distantPast) {
            lastHandledFocus = focus.at
            focusEvent = FocusEvent(tool: focus.tool, id: focus.at)
        }
        save()
    }

    private func reachabilityChanged(_ reachable: Bool) {
        let wasReachable = isReachable
        isReachable = reachable
        if reachable, !wasReachable { sayHello() }
    }

    // MARK: Cache

    private struct Cached: Codable {
        var state: StWatchState
        var receivedAt: Date?
    }

    private func save() {
        guard let cacheURL else { return }
        let cached = Cached(state: state, receivedAt: receivedAt)
        Task.detached(priority: .utility) { [logger] in
            do {
                try FileManager.default.createDirectory(
                    at: cacheURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try JSONEncoder().encode(cached).write(to: cacheURL, options: .atomic)
            } catch {
                logger.error("Falha ao salvar o estado do relógio: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

/// The `WCSession` delegate. Decodes off the main thread and hands each
/// state to the store on the main actor.
nonisolated private final class StWatchSessionLink: NSObject, WCSessionDelegate, @unchecked Sendable {
    @MainActor var onState: ((StWatchState) -> Void)?
    @MainActor var onReachability: ((Bool) -> Void)?

    private let queue = DispatchQueue(label: "dev.smartium.tools.watch.battery", qos: .utility)
    /// Battery sent before activation finished; sent once it does.
    private var pendingBattery: Data?

    private var session: WCSession? {
        WCSession.isSupported() ? WCSession.default : nil
    }

    func activate() {
        guard let session, session.activationState != .activated else { return }
        session.delegate = self
        session.activate()
    }

    /// Context for whenever the iPhone app runs, and a message when it is
    /// reachable now. This is the only data the watch sends (v0.11).
    func sendBattery(_ battery: StDeviceBattery) {
        guard let data = StWatchTransport.encode(battery) else { return }
        queue.async { [self] in
            guard let session, session.activationState == .activated else {
                pendingBattery = data
                return
            }
            send(battery: data, session: session)
        }
    }

    private func send(battery data: Data, session: WCSession) {
        let payload = [StWatchTransport.batteryKey: data]
        try? session.updateApplicationContext(payload)
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        }
    }

    func sayHello() {
        guard let session, session.activationState == .activated, session.isReachable else { return }
        session.sendMessage([StWatchTransport.helloKey: true], replyHandler: { [weak self] reply in
            self?.deliver(reply)
        }, errorHandler: nil)
    }

    private func deliver(_ payload: [String: Any]) {
        guard let state = StWatchTransport.decode(payload) else { return }
        Task { @MainActor in self.onState?(state) }
    }

    private func reachability(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in self.onReachability?(reachable) }
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if !session.receivedApplicationContext.isEmpty {
            deliver(session.receivedApplicationContext)
        }
        reachability(session)
        if activationState == .activated {
            queue.async { [self] in
                guard let pendingBattery else { return }
                self.pendingBattery = nil
                send(battery: pendingBattery, session: session)
            }
        }
        sayHello()
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        reachability(session)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        deliver(applicationContext)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        deliver(message)
    }
}
