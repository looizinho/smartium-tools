//
//  SmartiumLiveActivity.swift
//  My Game
//
//  ActivityKit attributes and LiveActivityManager for Dynamic Island support.
//

import AppIntents
import Foundation
import Observation

#if canImport(ActivityKit) && os(iOS)
import ActivityKit

/// ActivityAttributes shared between the main app and the Widget Extension for Dynamic Island sessions.
nonisolated public struct SmartiumActivityAttributes: ActivityAttributes, Sendable {
    nonisolated public struct ContentState: Codable, Hashable, Sendable {
        public var orbStateRaw: String
        public var statusText: String
        public var stepProgress: Double?
        public var updatedAt: Date

        public init(
            orbStateRaw: String = "working",
            statusText: String = "Working…",
            stepProgress: Double? = nil,
            updatedAt: Date = .now
        ) {
            self.orbStateRaw = orbStateRaw
            self.statusText = statusText
            self.stepProgress = stepProgress
            self.updatedAt = updatedAt
        }
    }

    public var toolIdentifier: String
    public var toolTitle: String

    public init(toolIdentifier: String = UUID().uuidString, toolTitle: String = "SmartiumTools") {
        self.toolIdentifier = toolIdentifier
        self.toolTitle = toolTitle
    }
}

@MainActor
extension SmartiumActivityAttributes.ContentState {
    /// Resolved `OrbState` on the main actor.
    public var orbState: OrbState {
        OrbState(rawValue: orbStateRaw) ?? .working
    }
}

/// Reusable manager for starting, updating, and ending Dynamic Island Live Activities
/// from any future SmartiumTools capability.
@MainActor
@Observable
public final class LiveActivityManager {
    public static let shared = LiveActivityManager()

    public private(set) var currentActivity: Activity<SmartiumActivityAttributes>?
    public private(set) var lastErrorMessage: String?

    private var animationTask: Task<Void, Never>?
    private var activityMonitorTask: Task<Void, Never>?

    public var isRunning: Bool {
        if let currentActivity,
           currentActivity.activityState == .active || currentActivity.activityState == .stale {
            return true
        }
        return !activeActivities.isEmpty
    }

    private var activeActivities: [Activity<SmartiumActivityAttributes>] {
        Activity<SmartiumActivityAttributes>.activities.filter {
            $0.activityState == .active || $0.activityState == .stale
        }
    }

    private init() {
        syncActiveActivity()
        observeActivities()
        if isRunning {
            startAnimationLoop()
        }
    }

    /// Synchronizes `currentActivity` with ActivityKit's live list of active sessions.
    public func syncActiveActivity() {
        currentActivity = activeActivities.first
    }

    private func observeActivities() {
        activityMonitorTask?.cancel()
        activityMonitorTask = Task { [weak self] in
            for await activity in Activity<SmartiumActivityAttributes>.activityUpdates {
                guard let self else { return }
                self.syncActiveActivity()
                self.startAnimationLoop()
                Task { [weak self] in
                    for await state in activity.activityStateUpdates {
                        guard let self else { return }
                        if state == .ended || state == .dismissed {
                            self.syncActiveActivity()
                            if !self.isRunning {
                                self.stopAnimationLoop()
                            }
                        }
                    }
                }
            }
        }
    }

    /// Starts a new Dynamic Island Live Activity or updates the existing one if already active.
    public func start(
        toolTitle: String = "SmartiumTools",
        initialState: OrbState = .working,
        progress: Double? = nil
    ) async {
        lastErrorMessage = nil
        ToolSharedState.updateOrbState(initialState, toolName: toolTitle, progress: progress)

        syncActiveActivity()
        if !activeActivities.isEmpty {
            await update(state: initialState, statusText: initialState.label, progress: progress)
            startAnimationLoop()
            return
        }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            lastErrorMessage = "As Atividades ao Vivo estão desativadas nos Ajustes."
            return
        }

        let attributes = SmartiumActivityAttributes(toolTitle: toolTitle)
        let contentState = SmartiumActivityAttributes.ContentState(
            orbStateRaw: initialState.rawValue,
            statusText: initialState.label,
            stepProgress: progress,
            updatedAt: .now
        )

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: contentState, staleDate: nil),
                pushType: nil
            )
            currentActivity = activity
            startAnimationLoop()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    /// Pushes a new `OrbState` and optional progress value to all active Dynamic Island sessions.
    public func update(
        state newOrbState: OrbState,
        statusText: String? = nil,
        progress: Double? = nil
    ) async {
        let activities = activeActivities
        guard !activities.isEmpty else {
            currentActivity = nil
            stopAnimationLoop()
            return
        }
        currentActivity = activities.first

        let updatedState = SmartiumActivityAttributes.ContentState(
            orbStateRaw: newOrbState.rawValue,
            statusText: statusText ?? newOrbState.label,
            stepProgress: progress,
            updatedAt: .now
        )
        let content = ActivityContent(state: updatedState, staleDate: nil)
        for activity in activities {
            await activity.update(content)
        }
        startAnimationLoop()
    }

    /// Ends all active SmartiumTools Live Activities immediately.
    public func stop() async {
        stopAnimationLoop()
        for activity in Activity<SmartiumActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        currentActivity = nil
    }

    /// Convenience toggle for quick testing in the base UI.
    public func toggle(toolTitle: String = "SmartiumTools", state: OrbState) async {
        syncActiveActivity()
        if isRunning {
            await stop()
        } else {
            await start(toolTitle: toolTitle, initialState: state)
        }
    }

    /// Periodically advances `updatedAt` on active Live Activities so the ThinkingOrb
    /// geometry evolves in the Dynamic Island and Lock Screen banner.
    private func startAnimationLoop() {
        guard animationTask == nil else { return }
        animationTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled, let self else { break }
                let activities = self.activeActivities
                guard !activities.isEmpty else {
                    self.currentActivity = nil
                    break
                }
                let shared = ToolSharedState.load()
                let orbState = shared.orbState
                let nextContentState = SmartiumActivityAttributes.ContentState(
                    orbStateRaw: orbState.rawValue,
                    statusText: orbState.label,
                    stepProgress: shared.stepProgress,
                    updatedAt: .now
                )
                let content = ActivityContent(state: nextContentState, staleDate: nil)
                for activity in activities {
                    await activity.update(content)
                }
            }
            // A canceled loop must not clear the handle of a replacement task.
            if !Task.isCancelled {
                self?.animationTask = nil
            }
        }
    }

    private func stopAnimationLoop() {
        animationTask?.cancel()
        animationTask = nil
    }
}

/// Interactive intent to stop the active Dynamic Island session directly from the expanded island.
/// Conforms to `LiveActivityIntent` so iOS runs it in the host app process.
public struct StopLiveActivityIntent: LiveActivityIntent {
    nonisolated public static let title: LocalizedStringResource = "Encerrar Atividade"
    nonisolated public static let description = IntentDescription(
        "Encerra a sessão ativa do SmartiumTools na Ilha Dinâmica."
    )

    nonisolated public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        await LiveActivityManager.shared.stop()
        return .result()
    }
}
#endif
