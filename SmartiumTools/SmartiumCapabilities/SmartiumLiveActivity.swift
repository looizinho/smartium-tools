//
//  SmartiumLiveActivity.swift
//  SmartiumTools
//
//  ActivityKit attributes and LiveActivityManager for Dynamic Island support.
//

import AppIntents
import Foundation
import Observation

#if canImport(ActivityKit) && os(iOS)
import ActivityKit
import UIKit

/// ActivityAttributes shared between the main app and the Widget Extension for Dynamic Island sessions.
nonisolated public struct SmartiumActivityAttributes: ActivityAttributes, Sendable {
    nonisolated public struct ContentState: Codable, Hashable, Sendable {
        public var orbStateRaw: String
        public var statusText: String
        public var stepProgress: Double?
        public var updatedAt: Date
        /// Absolute deadline for the latest activation or orb state change.
        public var animationEndsAt: Date?
        /// Tool that owns the activity (`StTool.rawValue`); its color tints the island.
        /// Optional so states encoded before v0.2 still decode.
        public var toolRaw: String?

        public init(
            orbStateRaw: String = "working",
            statusText: String = "Working…",
            stepProgress: Double? = nil,
            updatedAt: Date = .now,
            animationEndsAt: Date? = nil,
            toolRaw: String? = "orb"
        ) {
            self.orbStateRaw = orbStateRaw
            self.statusText = statusText
            self.stepProgress = stepProgress
            self.updatedAt = updatedAt
            self.animationEndsAt = animationEndsAt
            self.toolRaw = toolRaw
        }

        /// Owning tool; activities from before v0.2 are the Orb's.
        var tool: StTool {
            toolRaw.flatMap(StTool.init(rawValue:)) ?? .orb
        }

        /// A new state starts a fresh five-second window; progress-only updates do not.
        public mutating func changeOrbState(to rawValue: String, at now: Date) {
            guard orbStateRaw != rawValue else { return }
            orbStateRaw = rawValue
            updatedAt = now
            animationEndsAt = now.addingTimeInterval(5)
        }
    }

    public var toolIdentifier: String
    public var toolTitle: String

    public init(toolIdentifier: String = UUID().uuidString, toolTitle: String = "Orb") {
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
/// from any future SmartiumTools capability. Each change is one ActivityKit update;
/// the five-second highlight ends through the content's `staleDate`, so no
/// background loop competes with the next state change.
@MainActor
@Observable
public final class LiveActivityManager {
    public static let shared = LiveActivityManager()

    public private(set) var currentActivity: Activity<SmartiumActivityAttributes>?
    public private(set) var lastErrorMessage: String?

    private var activityMonitorTask: Task<Void, Never>?
    #if SMARTIUM_APP
    private var lifecycleTasks: [Task<Void, Never>] = []
    #endif

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
        #if SMARTIUM_APP
        observeLifecycle()
        #endif
    }

    /// Synchronizes `currentActivity` with ActivityKit's live list of active sessions.
    public func syncActiveActivity() {
        currentActivity = activeActivities.first
        // The Orb control reads this flag from the App Group (v0.5).
        let isActive = currentActivity != nil
        if StLiveSurfaces.isOrbActivityActive != isActive {
            StLiveSurfaces.isOrbActivityActive = isActive
            StLiveSurfaces.reloadControl(StLiveSurfaces.ControlKind.orb)
        }
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
        toolTitle: String = "Orb",
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
            updatedAt: .now,
            animationEndsAt: Date.now.addingTimeInterval(5),
            toolRaw: StTool.orb.rawValue
        )

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: contentState, staleDate: contentState.animationEndsAt),
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

        for activity in activities {
            var updatedState = activity.content.state
            updatedState.changeOrbState(to: newOrbState.rawValue, at: .now)
            updatedState.statusText = sharedState.statusMessage
            updatedState.stepProgress = sharedState.stepProgress
            await activity.update(ActivityContent(state: updatedState, staleDate: updatedState.animationEndsAt))
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

    #if SMARTIUM_APP
    private func observeLifecycle() {
        for name in [UIApplication.didBecomeActiveNotification,
                     UIApplication.didEnterBackgroundNotification] {
            lifecycleTasks.append(Task { [weak self] in
                for await _ in NotificationCenter.default.notifications(named: name) {
                    guard let self else { return }
                    self.syncActiveActivity()
                }
            })
        }
    }
    #endif

    /// Convenience toggle for quick testing in the base UI.
    public func toggle(toolTitle: String = "Orb", state: OrbState) async {
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
