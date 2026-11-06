//
//  MacTimerMenuBar.swift
//  SmartiumTools
//
//  Menu bar item for the Mac timer (handoff v0.7 §1): timer icon + `m:ss`
//  while a timer counts or is paused, hidden otherwise. Click opens a 280 pt
//  popover with a compact clock, pause/resume, ±1 min and cancel. It takes
//  the place of the Dynamic Island, and works with the window closed.
//

import SwiftUI

#if SMARTIUM_APP && os(macOS)
struct MacTimerMenuBar: Scene {
    @State private var service = StMacTimerService.shared

    var body: some Scene {
        MenuBarExtra(isInserted: Binding(get: { service.isActive }, set: { _ in })) {
            MacTimerPopover(service: service)
                .preferredColorScheme(.dark)
        } label: {
            // The system draws menu bar labels as templates, so the icon color
            // may not show; the paused state also dims the clock.
            HStack(spacing: 4) {
                Image(systemName: "timer")
                    .foregroundStyle(service.phase == .running ? StTool.timer.tone : .white.opacity(0.55))
                Text(MacTimerMenuBar.clock(service.remaining ?? 0))
                    .font(StFont.body(13, .semibold))
                    .monospacedDigit()
            }
            .accessibilityLabel("Timer \(MacTimerMenuBar.clock(service.remaining ?? 0))")
        }
        .menuBarExtraStyle(.window)
    }

    /// `m:ss`, or `h:mm:ss` from 1 h (§1).
    nonisolated static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let rest = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, rest)
            : String(format: "%d:%02d", minutes, rest)
    }
}

private struct MacTimerPopover: View {
    let service: StMacTimerService
    @Environment(\.openURL) private var openURL

    var body: some View {
        let timer = StTool.timer
        VStack(spacing: 14) {
            VStack(spacing: 2) {
                Text(service.phase == .paused ? "PAUSADO" : "RESTANTE")
                    .font(.stTag)
                    .tracking(1.4)
                    .foregroundStyle(StAccent.sky.color)
                StBigNumber(TimerFormat.duration(service.remaining ?? 0), size: 44)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)

            HStack(spacing: 10) {
                StButton(
                    service.phase == .running ? "Pausar" : "Retomar",
                    systemImage: service.phase == .running ? "pause.fill" : "play.fill",
                    kind: .iconTinted(.timer)
                ) {
                    service.toggle()
                }
                StButton("Menos 1 minuto", systemImage: "minus", kind: .iconTinted(.fx)) {
                    service.adjust(by: -60)
                }
                StButton("Mais 1 minuto", systemImage: "plus", kind: .iconTinted(.timer)) {
                    service.adjust(by: 60)
                }
                StButton("Cancelar", systemImage: "xmark", kind: .iconTinted(.voice)) {
                    service.cancel()
                }
            }

            // v0.8: opens the window on the Timer tab.
            StButton("Abrir Timer", systemImage: "macwindow", kind: .tonal) {
                openURL(StToolDestination.timer.url)
            }
        }
        .padding(18)
        .frame(width: 280)
        .background(
            LinearGradient(
                stops: [
                    .init(color: timer.opacity(0.14), location: 0),
                    .init(color: .stInk800, location: 0.7)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .font(StFont.body(15))
        .environment(\.colorScheme, .dark)
    }
}
#endif
