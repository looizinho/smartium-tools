//
//  SmartiumSharedState.swift
//  SmartiumTools
//
//  Shared state & AppIntents foundation for SmartiumTools Widgets and Dynamic Island.
//

import AppIntents
import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif
#if canImport(ActivityKit) && os(iOS)
import ActivityKit
#endif

public extension Notification.Name {
    static let smartiumOrbStateDidChange = Notification.Name("dev.smartium.tools.orbStateDidChange")
}

/// Shared state persisted inside the `group.dev.smartium.tests` App Group container
/// so the main app, Home Screen Widgets, and Live Activities stay in sync.
nonisolated public struct ToolSharedState: Codable, Sendable, Equatable {
    public static let appGroupIdentifier = "group.dev.smartium.tests"
    private static let storageKey = "dev.smartium.tools.sharedState"

    public var activeToolName: String
    public var orbStateRaw: String
    public var statusMessage: String
    public var stepProgress: Double?
    public var updatedAt: Date

    public init(
        activeToolName: String = "SmartiumTools",
        orbStateRaw: String = "working",
        statusMessage: String = "Working…",
        stepProgress: Double? = nil,
        updatedAt: Date = .now
    ) {
        self.activeToolName = activeToolName
        self.orbStateRaw = orbStateRaw
        self.statusMessage = statusMessage
        self.stepProgress = stepProgress
        self.updatedAt = updatedAt
    }

    /// Reads the latest shared state from the App Group container, falling back to `UserDefaults.standard`.
    public static func load() -> ToolSharedState {
        let defaults = UserDefaults(suiteName: appGroupIdentifier) ?? .standard
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(ToolSharedState.self, from: data) else {
            return ToolSharedState()
        }
        return decoded
    }

    /// Saves the state to the App Group container and requests a WidgetKit timeline reload.
    public func save(reloadWidgets: Bool = true) {
        let defaults = UserDefaults(suiteName: Self.appGroupIdentifier) ?? .standard
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.storageKey)
        }
        #if canImport(WidgetKit)
        if reloadWidgets {
            WidgetCenter.shared.reloadAllTimelines()
        }
        #endif
    }
}

@MainActor
extension ToolSharedState {
    /// Resolved `OrbState` for UI and Canvas rendering.
    public var orbState: OrbState {
        get { OrbState(rawValue: orbStateRaw) ?? .working }
        set {
            orbStateRaw = newValue.rawValue
            statusMessage = newValue.label
            updatedAt = .now
        }
    }

    /// Updates the shared orb state, persists it to the App Group, and reloads Widgets.
    @discardableResult
    public static func updateOrbState(
        _ newState: OrbState,
        toolName: String = "SmartiumTools",
        progress: Double? = nil
    ) -> ToolSharedState {
        var state = load()
        state.activeToolName = toolName
        state.orbState = newState
        state.stepProgress = progress
        state.updatedAt = .now
        state.save(reloadWidgets: true)
        NotificationCenter.default.post(name: .smartiumOrbStateDidChange, object: newState)
        return state
    }

    /// Advances to the next state in `OrbState.allCases` and persists the result.
    @discardableResult
    public static func advanceToNextOrbState() -> ToolSharedState {
        var state = load()
        let allStates = OrbState.allCases
        let current = state.orbState
        if let index = allStates.firstIndex(of: current) {
            let next = allStates[(index + 1) % allStates.count]
            state.orbState = next
        } else {
            state.orbState = .working
        }
        state.updatedAt = .now
        state.save(reloadWidgets: true)
        NotificationCenter.default.post(name: .smartiumOrbStateDidChange, object: state.orbState)
        return state
    }
}

// MARK: - Interactive Widget & Dynamic Island AppIntents

/// Interactive intent that cycles the active `OrbState` directly from a Home Screen Widget
/// or Dynamic Island expanded button without opening the app.
/// Conforms to `LiveActivityIntent` on iOS so the system executes it in the app process,
/// allowing direct access to `Activity<SmartiumActivityAttributes>.activities`.
#if canImport(ActivityKit) && os(iOS)
public struct CycleOrbStateIntent: LiveActivityIntent {
    nonisolated public static let title: LocalizedStringResource = "Alternar Estado do Orbe"
    nonisolated public static let description = IntentDescription(
        "Avança o ThinkingOrb para o próximo estado no SmartiumTools."
    )

    nonisolated public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        let updated = ToolSharedState.advanceToNextOrbState()
        await LiveActivityManager.shared.update(
            state: updated.orbState,
            statusText: updated.statusMessage,
            progress: updated.stepProgress
        )
        return .result()
    }
}
#else
public struct CycleOrbStateIntent: AppIntent {
    nonisolated public static let title: LocalizedStringResource = "Alternar Estado do Orbe"
    nonisolated public static let description = IntentDescription(
        "Avança o ThinkingOrb para o próximo estado no SmartiumTools."
    )

    nonisolated public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        ToolSharedState.advanceToNextOrbState()
        return .result()
    }
}
#endif
