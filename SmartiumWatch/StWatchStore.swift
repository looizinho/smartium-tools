//
//  StWatchStore.swift
//  SmartiumWatch
//
//  Watch side of the bridge (handoff v0.10 §3): receives `StWatchState` from
//  the iPhone, keeps the last one on disk so the app opens with it even
//  without a connection, and says when the data is stale.
//

import Foundation
import Observation
import OSLog
import WatchConnectivity

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

    struct FocusEvent: Equatable {
        let tool: StToolDestination
        let id: Date
    }

    @ObservationIgnored private let link = StWatchSessionLink()
    @ObservationIgnored private let cacheURL: URL?
    @ObservationIgnored private let logger = Logger(subsystem: "dev.smartium.tools.watch", category: "sync")
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

    /// On opening or becoming active: the iPhone answers with its state.
    func sayHello() {
        link.sayHello()
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

    private var session: WCSession? {
        WCSession.isSupported() ? WCSession.default : nil
    }

    func activate() {
        guard let session, session.activationState != .activated else { return }
        session.delegate = self
        session.activate()
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
