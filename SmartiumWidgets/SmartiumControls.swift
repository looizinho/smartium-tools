//
//  SmartiumControls.swift
//  SmartiumWidgets
//
//  Control Center: one control per tool (handoff v0.5). On, the control fills
//  with the tool color (`.tint`). Values come from the App Group snapshots.
//

import AppIntents
import SwiftUI
import WidgetKit

#if os(iOS)
struct SmartiumOrbControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: StLiveSurfaces.ControlKind.orb, provider: Provider()) { isOn in
            ControlWidgetToggle("Live Activity", isOn: isOn, action: ToggleOrbActivityIntent()) { isOn in
                Label(isOn ? "Ativa" : "Desligada", systemImage: StTool.orb.systemImage)
            }
            .tint(StTool.orb.tone)
        }
        .displayName("Orb")
        .description("Liga e desliga a Live Activity do Orb.")
    }

    struct Provider: ControlValueProvider {
        var previewValue: Bool { false }

        func currentValue() async throws -> Bool {
            StLiveSurfaces.isOrbActivityActive
        }
    }
}

struct SmartiumVoiceControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: StLiveSurfaces.ControlKind.voice) {
            // Dictation isn't implemented yet, so the control is never on.
            ControlWidgetToggle("Ditado", isOn: false, action: ToggleDictationIntent()) { isOn in
                Label(isOn ? "Ouvindo…" : "Toque para falar", systemImage: StTool.voice.systemImage)
            }
            .tint(StTool.voice.tone)
        }
        .displayName("Voz")
        .description("Abre a Voz para ditar.")
    }
}

#if canImport(AlarmKit)
struct SmartiumTimerControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: StLiveSurfaces.ControlKind.timer, provider: Provider()) { snapshot in
            let now = Date.now
            let phase = snapshot.phase(at: now)
            ControlWidgetToggle(isOn: phase == .running, action: ToggleTimerIntent()) {
                Label("Timer", systemImage: StTool.timer.systemImage)
            } valueLabel: { _ in
                switch phase {
                case .running:
                    Text(timerInterval: now...(snapshot.fireDate ?? now), countsDown: true)
                case .paused:
                    Text("Pausado · \(StTimerSnapshot.format(snapshot.remaining(at: now)))")
                case .idle, .alerting:
                    Text("Pronto")
                }
            }
            .tint(StTool.timer.tone)
        }
        .displayName("Timer")
        .description("Pausa e retoma o timer.")
    }

    struct Provider: ControlValueProvider {
        var previewValue: StTimerSnapshot { StTimerSnapshot() }

        func currentValue() async throws -> StTimerSnapshot {
            StLiveSurfaces.timer
        }
    }
}
#endif

struct SmartiumStagingControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: StLiveSurfaces.ControlKind.staging) {
            ControlWidgetButton(action: OpenToolIntent(tool: .staging)) {
                Label {
                    Text("Staging")
                    Text("Abrir câmera")
                } icon: {
                    Image(systemName: StTool.fx.systemImage)
                }
            }
            .tint(StTool.fx.tone)
        }
        .displayName("Staging")
        .description("Abre a câmera do Staging.")
    }
}

struct SmartiumMonitorControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: StLiveSurfaces.ControlKind.monitor, provider: Provider()) { cpu in
            ControlWidgetButton(action: OpenToolIntent(tool: .monitor)) {
                Label {
                    Text("Monitor")
                    Text(cpu.map { "CPU \($0)%" } ?? "CPU —")
                } icon: {
                    Image(systemName: StTool.monitor.systemImage)
                }
            }
            .tint(StTool.monitor.tone)
        }
        .displayName("Monitor")
        .description("Abre o Monitor.")
    }

    struct Provider: ControlValueProvider {
        var previewValue: Int? { 32 }

        func currentValue() async throws -> Int? {
            StLiveSurfaces.metrics.map { Int(($0.cpu * 100).rounded()) }
        }
    }
}
#endif
