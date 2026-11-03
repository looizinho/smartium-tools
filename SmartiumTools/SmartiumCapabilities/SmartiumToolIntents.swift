//
//  SmartiumToolIntents.swift
//  SmartiumTools
//
//  Intents shared by the Control Center controls and the widgets (handoff v0.5).
//  Compiled into both targets; the work happens in the app process, so the
//  bodies that need app-only code sit behind `SMARTIUM_APP`.
//

import AppIntents
import Foundation

/// Opens the app on a tab (Staging and Monitor controls).
struct OpenToolIntent: OpenIntent {
    static let title: LocalizedStringResource = "Abrir ferramenta"
    static let description = IntentDescription("Abre o SmartiumTools na ferramenta escolhida.")

    @Parameter(title: "Ferramenta")
    var target: StToolDestination

    init() {}

    init(tool: StToolDestination) {
        target = tool
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        StLiveSurfaces.requestTool(target)
        NotificationCenter.default.post(name: .smartiumOpenToolRequested, object: nil)
        return .result()
    }
}

/// Voz control: opens the Voz tab. Dictation itself is still a placeholder,
/// so the control never reports "on".
struct ToggleDictationIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Ditado"
    static let description = IntentDescription("Abre o SmartiumTools na Voz para ditar.")
    static let supportedModes: IntentModes = .foreground(.immediate)

    @Parameter(title: "Ouvindo")
    var value: Bool

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        StLiveSurfaces.requestTool(.voice)
        NotificationCenter.default.post(name: .smartiumOpenToolRequested, object: nil)
        return .result()
    }
}

#if canImport(ActivityKit) && os(iOS)
/// Orb control: turns the Orb's Live Activity on or off.
struct ToggleOrbActivityIntent: SetValueIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Live Activity do Orb"
    static let description = IntentDescription("Liga ou desliga a Live Activity do Orb.")

    @Parameter(title: "Ativa")
    var value: Bool

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        let manager = LiveActivityManager.shared
        manager.syncActiveActivity()
        if value, !manager.isRunning {
            await manager.start(toolTitle: "Orb", initialState: ToolSharedState.load().orbState)
        } else if !value {
            await manager.stop()
        }
        manager.syncActiveActivity()
        return .result()
    }
}
#endif

#if canImport(AlarmKit) && os(iOS)
/// Timer control and widget: `true` resumes (or starts the last duration), `false` pauses.
struct ToggleTimerIntent: SetValueIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Pausar ou retomar o timer"
    static let description = IntentDescription("Pausa ou retoma o timer do SmartiumTools.")

    @Parameter(title: "Contando")
    var value: Bool

    init() {}

    init(running: Bool) {
        value = running
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        #if SMARTIUM_APP
        try await StTimerService.setRunning(value)
        #endif
        return .result()
    }
}

/// AlarmKit runs this when the ringing timer is stopped from the system alert,
/// so widgets and the control show "Pronto" right away.
struct StopTimerIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Parar o timer"
    static let description = IntentDescription("Para o timer do SmartiumTools.")
    static let isDiscoverable = false

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        #if SMARTIUM_APP
        StTimerService.markStopped()
        #endif
        return .result()
    }
}

/// Timer widget: counts the full duration again from the start.
struct ResetTimerIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Reiniciar o timer"
    static let description = IntentDescription("Recomeça o timer do SmartiumTools do início.")

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        #if SMARTIUM_APP
        try await StTimerService.restart()
        #endif
        return .result()
    }
}
#endif
