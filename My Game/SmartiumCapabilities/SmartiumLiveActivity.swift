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
import UIKit

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
/// from any future SmartiumTools capability. Animation updates preserve the
/// activity content and run only while iOS grants the app execution time.
@MainActor
@Observable
public final class LiveActivityManager {
    public static let shared = LiveActivityManager()

    public private(set) var currentActivity: Activity<SmartiumActivityAttributes>?
    public private(set) var lastErrorMessage: String?

    private var activityMonitorTask: Task<Void, Never>?
    #if SMARTIUM_APP
    private var lifecycleTasks: [Task<Void, Never>] = []
    private var animationTask: Task<Void, Never>?
    private var animationGeneration = UUID()
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private var backgroundTimeExpired = false
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
        reconcileAnimation()
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
            reconcileAnimation()
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
            stopAnimation()
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
        reconcileAnimation()
    }

    /// Ends all active SmartiumTools Live Activities immediately.
    public func stop() async {
        stopAnimation()
        lastErrorMessage = nil
        for activity in Activity<SmartiumActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        currentActivity = nil
    }

    #if SMARTIUM_APP
    private func observeLifecycle() {
        for name in [UIApplication.didBecomeActiveNotification,
                     UIApplication.didEnterBackgroundNotification,
                     UIAccessibility.reduceMotionStatusDidChangeNotification] {
            lifecycleTasks.append(Task { [weak self] in
                for await _ in NotificationCenter.default.notifications(named: name) {
                    guard let self else { return }
                    if name == UIApplication.didBecomeActiveNotification {
                        self.backgroundTimeExpired = false
                    }
                    self.syncActiveActivity()
                }
            })
        }
    }

    private func reconcileAnimation() {
        guard isRunning, !UIAccessibility.isReduceMotionEnabled,
              !backgroundTimeExpired else {
            stopAnimation()
            return
        }
        if UIApplication.shared.applicationState == .background {
            if backgroundTaskID == .invalid {
                backgroundTaskID = UIApplication.shared.beginBackgroundTask(
                    withName: "SmartiumOrbAnimation"
                ) { [weak self] in
                    self?.backgroundTimeExpired = true
                    self?.stopAnimation()
                }
            }
            guard backgroundTaskID != .invalid else {
                stopAnimation()
                return
            }
        } else {
            endBackgroundTask()
        }
        guard animationTask == nil else { return }
        let generation = UUID()
        animationGeneration = generation
        animationTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .milliseconds(350))
                } catch {
                    break
                }
                guard let self, !Task.isCancelled else { break }
                let activities = self.activeActivities
                guard !activities.isEmpty else { break }
                for activity in activities {
                    guard !Task.isCancelled else { break }
                    // Advance geometry without replacing custom status/progress
                    // or writing animation ticks to shared storage and widgets.
                    var state = activity.content.state
                    state.updatedAt = .now
                    await activity.update(ActivityContent(state: state, staleDate: nil))
                }
            }
            // A canceled task must not clear a replacement loop's handle.
            if let self, self.animationGeneration == generation {
                self.animationTask = nil
                self.endBackgroundTask()
            }
        }
    }

    private func stopAnimation() {
        animationGeneration = UUID()
        animationTask?.cancel()
        animationTask = nil
        endBackgroundTask()
    }

    private func endBackgroundTask() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }

    #else
    // LiveActivityIntents execute in the host app. The extension only renders
    // snapshots and must not acquire UIApplication background execution time.
    private func reconcileAnimation() {}
    private func stopAnimation() {}
    #endif

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
