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
/// from any future SmartiumTools capability. Content updates are event-driven;
/// Live Activities keep their last snapshot while the app is suspended.
@MainActor
@Observable
public final class LiveActivityManager {
    public static let shared = LiveActivityManager()

    public private(set) var currentActivity: Activity<SmartiumActivityAttributes>?
    public private(set) var lastErrorMessage: String?

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
                Task { [weak self] in
                    for await state in activity.activityStateUpdates {
                        guard let self else { return }
                        if state == .ended || state == .dismissed {
                            self.syncActiveActivity()
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
        // Persist first so app, widgets, and the activity share the same content,
        // including updates received when there is no active Live Activity.
        var sharedState = ToolSharedState.load()
        sharedState.orbState = newOrbState
        sharedState.statusMessage = statusText ?? newOrbState.label
        sharedState.stepProgress = progress
        sharedState.save()
        NotificationCenter.default.post(name: .smartiumOrbStateDidChange, object: newOrbState)

        let activities = activeActivities
        guard !activities.isEmpty else {
            currentActivity = nil
            return
        }
        currentActivity = activities.first

        let updatedState = SmartiumActivityAttributes.ContentState(
            orbStateRaw: newOrbState.rawValue,
            statusText: sharedState.statusMessage,
            stepProgress: sharedState.stepProgress,
            updatedAt: sharedState.updatedAt
        )
        let content = ActivityContent(state: updatedState, staleDate: nil)
        for activity in activities {
            await activity.update(content)
        }
    }

    /// Ends all active SmartiumTools Live Activities immediately.
    public func stop() async {
        lastErrorMessage = nil
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
