//
//  MacTimerView.swift
//  SmartiumTools
//
//  Timer screen on the Mac (handoff v0.7), built from the same St* pieces as
//  the iPhone screen but driven by `StMacTimerService` instead of AlarmKit.
//  The hero is always visible on the Mac (v0.4). Adds the "Toque" choice,
//  which only exists here (§3).
//

import SwiftUI

#if SMARTIUM_APP && os(macOS)
struct MacTimerView: View {
    @State private var service = StMacTimerService.shared
    @State private var selectedHours = 0
    @State private var selectedMinutes = 5
    @State private var selectedSeconds = 0

    var body: some View {
        StAdaptiveToolLayout(tool: .timer, tag: "Timer") { size in
            let remaining = service.remaining
            let total = service.total > 0 ? service.total : selectedDuration
            StTimerRing(
                size: size,
                fraction: remaining.map { total > 0 ? $0 / total : 0 } ?? 1,
                label: remaining == nil ? "DEFINIDO" : "RESTANTE",
                clock: TimerFormat.duration(remaining ?? selectedDuration),
                status: ringStatus
            )
        } controls: {
            StToolHeader(
                title: "Timer",
                subtitle: headerStatus.title,
                tool: .timer,
                status: headerStatus.dot
            )
            if service.notificationsDenied {
                notificationsWarning
            }
            durationPicker
            controls
            messageField
            StChipSection(
                title: "Atalhos",
                dot: StTool.timer.secondary,
                items: TimerAdjustment.all,
                label: \.title,
                color: \.color,
                isOn: { _ in false },
                select: adjust
            )
            ringerSection
            if !service.limitimer.recents.isEmpty {
                recents
            }
        }
        .task {
            await service.load()
        }
    }

    private var selectedDuration: TimeInterval {
        Double(selectedHours * 3_600 + selectedMinutes * 60 + selectedSeconds)
    }

    private var headerStatus: (title: String, dot: StHeaderStatus) {
        switch service.phase {
        case .running: ("Em andamento", .active)
        case .paused: ("Pausado", .ready)
        case .alerting: ("Encerrado!", .active)
        case .idle: ("Pronto para iniciar", .configured)
        }
    }

    private var ringStatus: String {
        switch service.phase {
        case .running: "Em andamento…"
        case .paused: "Pausado"
        case .alerting: "Encerrado!"
        case .idle: "Pronto"
        }
    }

    // MARK: Notifications

    /// §2: permission refused, so the end alert only works with the app open.
    private var notificationsWarning: some View {
        let amber = StTool.fx
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: "bell.slash.fill")
                .font(StFont.body(16, .semibold))
                .foregroundStyle(amber.tone)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Notificações desligadas")
                    .font(StFont.body(14, .semibold))
                    .foregroundStyle(amber.tone)
                Text("O aviso de fim só toca com o app aberto. Ative em Ajustes do Sistema › Notificações.")
                    .font(StFont.body(13))
                    .foregroundStyle(Color.stTextPrimary.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(amber.opacity(0.10)))
        .accessibilityElement(children: .combine)
    }

    // MARK: Picker

    /// The Mac has no wheel pickers: three menus with the same limits as the
    /// iPhone (h 0–2, min/s 0–59, at most 2:00:00), disabled while counting.
    private var durationPicker: some View {
        let isAtMaxHours = selectedHours == Int(StTimer.maxDuration) / 3_600
        return HStack(spacing: 10) {
            picker(selection: $selectedHours, range: 0...(Int(StTimer.maxDuration) / 3_600), label: "Horas", unit: "h")
            picker(selection: $selectedMinutes, range: isAtMaxHours ? 0...0 : 0...59, label: "Minutos", unit: "min")
            picker(selection: $selectedSeconds, range: isAtMaxHours ? 0...0 : 0...59, label: "Segundos", unit: "s")
        }
        .onChange(of: isAtMaxHours) { _, isAtMax in
            if isAtMax {
                selectedMinutes = 0
                selectedSeconds = 0
            }
        }
        .disabled(service.phase != .idle)
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.stInk800)
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(.white.opacity(0.06), lineWidth: 1)
                )
        )
    }

    private func picker(selection: Binding<Int>, range: ClosedRange<Int>, label: String, unit: String) -> some View {
        Picker(label, selection: selection) {
            ForEach(range, id: \.self) { value in
                Text("\(value) \(unit)").tag(value)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .font(StFont.body(16, .semibold))
        .frame(maxWidth: .infinity)
    }

    // MARK: Controls

    private var controls: some View {
        HStack(spacing: 10) {
            primaryButton
            StButton("Zerar", systemImage: "arrow.counterclockwise", kind: .iconTinted(.voice)) {
                service.cancel()
            }
            .disabled(service.phase == .idle)
        }
    }

    private var primaryButton: some View {
        let (title, symbol): (LocalizedStringKey, String) = switch service.phase {
        case .running: ("Pausar", "pause.fill")
        case .paused: ("Retomar", "play.fill")
        case .alerting: ("Parar", "stop.fill")
        case .idle: ("Iniciar", "play.fill")
        }

        return StButton(title, systemImage: symbol, kind: .primary(.timer)) {
            if service.phase == .idle {
                service.start(duration: selectedDuration, message: service.limitimer.endMessage)
            } else {
                service.toggle()
            }
        }
        .disabled(service.phase == .idle && selectedDuration == 0)
    }

    private var messageField: some View {
        let sky = StAccent.sky
        let shape = RoundedRectangle(cornerRadius: StRadius.row, style: .continuous)
        return HStack(spacing: 12) {
            Image(systemName: "text.bubble")
                .font(StFont.body(17, .semibold))
                .foregroundStyle(sky.color)
                .frame(width: 38, height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(sky.color(opacity: 0.16))
                )
                .accessibilityHidden(true)
            TextField("Mensagem de encerramento", text: $service.limitimer.endMessage)
                .textFieldStyle(.plain)
                .font(StFont.body(16, .medium))
                .foregroundStyle(Color.stTextPrimary)
        }
        .padding(.leading, 10)
        .padding(.trailing, 16)
        .frame(height: 58)
        .background(shape.fill(Color.stInk800))
        .overlay(shape.strokeBorder(sky.color(opacity: 0.22), lineWidth: 1))
    }

    /// Stopped: changes the set time. Counting or paused: changes the
    /// remaining time (the service reschedules the notification).
    private func adjust(_ adjustment: TimerAdjustment) {
        switch service.phase {
        case .idle:
            applyDuration(Int(selectedDuration) + adjustment.seconds)
        case .running, .paused:
            service.adjust(by: TimeInterval(adjustment.seconds))
        case .alerting:
            break
        }
    }

    /// Sets the pickers, clamped to 0…`StTimer.maxDuration`.
    private func applyDuration(_ seconds: Int) {
        let seconds = min(Int(StTimer.maxDuration), max(0, seconds))
        selectedHours = seconds / 3_600
        selectedMinutes = (seconds % 3_600) / 60
        selectedSeconds = seconds % 60
    }

    // MARK: Ringer

    /// §3 "Toque": system sound, one of the app's sounds (with a preview), or
    /// silent. Lives here until the app has a Settings screen.
    private var ringerSection: some View {
        let rings = StTimerRinger.allCases
        return VStack(alignment: .leading, spacing: 8) {
            StChipSection(
                title: "Toque",
                dot: StTool.timer.secondary,
                items: rings,
                label: \.title,
                color: { ringer in
                    ringer == .silent ? StAccent.mono : StAccent.color(at: rings.firstIndex(of: ringer) ?? 0)
                },
                isOn: { $0 == service.limitimer.ringer },
                select: { ringer in
                    service.limitimer.ringer = ringer
                    service.preview(ringer)
                }
            )
            Text("Com o app fechado, vale o som da notificação.")
                .font(StFont.body(13))
                .foregroundStyle(Color.stTextPrimary.opacity(0.5))
                .padding(.horizontal, 4)
        }
    }

    // MARK: Recents

    private var recents: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recentes")
                .font(StFont.body(20, .bold))
                .padding(.top, 8)
                .padding(.horizontal, 4)
                .accessibilityAddTraits(.isHeader)

            ForEach(Array(service.limitimer.recents.enumerated()), id: \.element.id) { index, recent in
                recentRow(recent, color: [StAccent.sky, StTool.voice.rgb, StTool.fx.rgb, StTool.orb.rgb][index % 4])
                    .contextMenu {
                        Button("Apagar", systemImage: "trash", role: .destructive) {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                service.limitimer = service.limitimer.removingRecent(id: recent.id)
                            }
                        }
                    }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func recentRow(_ recent: LimitimerRecent, color: StRGB) -> some View {
        let shape = RoundedRectangle(cornerRadius: StRadius.row, style: .continuous)
        return HStack(alignment: .center, spacing: 14) {
            Image(systemName: "timer")
                .font(StFont.body(19, .semibold))
                .foregroundStyle(color.color)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(color.color(opacity: 0.16))
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                StBigNumber(TimerFormat.duration(recent.duration), size: 24)
                Text(recent.message.isEmpty ? "Sem mensagem" : recent.message)
                    .font(StFont.body(13))
                    .foregroundStyle(Color.stTextPrimary.opacity(0.55))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button {
                applyDuration(Int(recent.duration))
                service.start(duration: recent.duration, message: recent.message)
            } label: {
                Image(systemName: "play.fill")
                    .font(StFont.body(15, .bold))
                    .foregroundStyle(StTool.timer.tone)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(StTool.timer.opacity(0.16)))
            }
            .buttonStyle(StPressStyle())
            .accessibilityLabel("Iniciar \(TimerFormat.duration(recent.duration))")
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(Color.stInk800))
        .overlay(shape.strokeBorder(.white.opacity(0.05), lineWidth: 1))
    }
}
#endif
