//
//  StWatchSync.swift
//  SmartiumTools
//
//  iPhone side of the watch bridge (handoff v0.10 §3). Keeps an
//  `StWatchState` and sends it with `updateApplicationContext` (the system
//  delivers the latest when the watch wakes). User actions also go out at
//  once with `sendMessage` while the watch app is reachable, and so do
//  Monitor samples. Since v0.11 the watch sends its battery back, which goes
//  to `StDeviceSync`, and the state carries every device's battery.
//  App-only and iOS-only.
//

import Foundation

#if SMARTIUM_APP && os(iOS) && canImport(WatchConnectivity)
import WatchConnectivity

@MainActor
final class StWatchSync {
    static let shared = StWatchSync()

    /// Context updates carrying only new samples, at most this often.
    private static let sampleContextInterval: TimeInterval = 30

    private(set) var state = StWatchState()
    private let link = StWatchLink()
    private var lastSampleContext: Date?

    private init() {
        state.order = StWatchState.order(from: StSettingsStore.shared.settings.tabOrder)
        state.timer = StLiveSurfaces.timer
        state.monitor.pinned = StSettingsStore.shared.settings.monitor.pinnedMetric
        state.monitor.snapshot = StLiveSurfaces.metrics
        state.devices = StDeviceSync.shared.devices
        link.currentState = { [weak self] in
            self?.stamped()
        }
    }

    /// Activates the session. Call once at launch.
    func activate() {
        link.activate()
        link.updateContext(stamped())
    }

    // MARK: Changes

    func timerChanged(_ snapshot: StTimerSnapshot) {
        guard snapshot != state.timer else { return }
        // Reaching the end on its own is not a user action.
        let isAction = snapshot.phase != .alerting
        state.timer = snapshot
        send(focus: isAction ? .timer : nil)
    }

    func voiceModeChanged(_ mode: String) {
        guard mode != state.voice.mode else { return }
        state.voice.mode = mode
        send(focus: .voice)
    }

    func pinnedMetricChanged(_ pinned: String?, isUserAction: Bool) {
        guard pinned != state.monitor.pinned else { return }
        state.monitor.pinned = pinned
        state.monitor.detail = ""
        send(focus: isUserAction ? .monitor : nil)
    }

    func tabOrderChanged(_ tabOrder: [String]) {
        let order = StWatchState.order(from: tabOrder)
        guard order != state.order else { return }
        state.order = order
        send(focus: nil)
    }

    /// The device batteries changed (v0.11).
    func devicesChanged(_ devices: [StDeviceBattery]) {
        guard devices != state.devices else { return }
        state.devices = devices
        send(focus: nil)
    }

    /// A Monitor sample: live to an open watch app, and into the context at
    /// most every 30 s so the transfer budget lasts.
    func metricsSampled(_ snapshot: StMetricsSnapshot, detail: String) {
        state.monitor.snapshot = snapshot
        state.monitor.detail = detail
        let current = stamped()
        link.sendMessageIfReachable(current)
        if let lastSampleContext, Date.now.timeIntervalSince(lastSampleContext) < Self.sampleContextInterval { return }
        lastSampleContext = .now
        link.updateContext(current)
    }

    // MARK: Sending

    private func send(focus tool: StToolDestination?) {
        if let tool { state.focus = .init(tool: tool, at: .now) }
        let current = stamped()
        link.updateContext(current)
        if tool != nil { link.sendMessageIfReachable(current) }
    }

    private func stamped() -> StWatchState {
        state.sentAt = .now
        return state
    }
}

/// The `WCSession` delegate. Sends happen on a serial queue, off the main
/// thread; the state is a value type, so nothing is shared across threads.
nonisolated private final class StWatchLink: NSObject, WCSessionDelegate, @unchecked Sendable {
    /// Returns the current state on the main actor (the "hello" reply).
    @MainActor var currentState: (() -> StWatchState?)?

    private let queue = DispatchQueue(label: "dev.smartium.tools.watchSync", qos: .utility)
    /// Last context sent before activation finished; sent once it does.
    private var pending: Data?

    private var session: WCSession? {
        WCSession.isSupported() ? WCSession.default : nil
    }

    func activate() {
        guard let session else { return }
        session.delegate = self
        session.activate()
    }

    func updateContext(_ state: StWatchState) {
        guard let data = StWatchTransport.encode(state) else { return }
        queue.async { [self] in
            guard let session, session.activationState == .activated else {
                pending = data
                return
            }
            guard session.isPaired, session.isWatchAppInstalled else { return }
            try? session.updateApplicationContext([StWatchTransport.stateKey: data])
        }
    }

    func sendMessageIfReachable(_ state: StWatchState) {
        guard let data = StWatchTransport.encode(state) else { return }
        queue.async { [self] in
            guard let session, session.activationState == .activated, session.isReachable else { return }
            session.sendMessage([StWatchTransport.stateKey: data], replyHandler: nil, errorHandler: nil)
        }
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if activationState == .activated {
            receiveBattery(session.receivedApplicationContext)
        }
        queue.async { [self] in
            guard activationState == .activated, let data = pending else { return }
            pending = nil
            guard session.isPaired, session.isWatchAppInstalled else { return }
            try? session.updateApplicationContext([StWatchTransport.stateKey: data])
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        // Switching watches: activate again for the new one.
        session.activate()
    }

    /// The watch's battery (v0.11), from its context or a message.
    private func receiveBattery(_ payload: [String: Any]) {
        guard let battery = StWatchTransport.decodeBattery(payload) else { return }
        Task { @MainActor in StDeviceSync.shared.receiveWatch(battery) }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        receiveBattery(applicationContext)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        receiveBattery(message)
    }

    /// The watch's "hello": answer with the current state.
    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        receiveBattery(message)
        guard message[StWatchTransport.helloKey] != nil else {
            replyHandler([:])
            return
        }
        let reply = SendableReply(replyHandler)
        Task { @MainActor in
            let data = self.currentState?().flatMap(StWatchTransport.encode)
            reply.call(data.map { [StWatchTransport.stateKey: $0] } ?? [:])
        }
    }
}

/// Carries the WatchConnectivity reply handler to the main actor.
nonisolated private struct SendableReply: @unchecked Sendable {
    let call: ([String: Any]) -> Void

    init(_ call: @escaping ([String: Any]) -> Void) {
        self.call = call
    }
}
#endif
