//
//  ContentView.swift
//  SmartiumTools
//
//  Created by Luiz Neto on 27/10/26.
//

import SwiftUI

/// The app's tools, mapped to their design-system color. The raw value is the
/// ID in `settings.json` `tabOrder`; `allCases` is the default order.
enum ToolTab: String, Hashable, CaseIterable {
  case orb
  case voice
  case timer
  case staging
  case monitor

  var tool: StTool {
    switch self {
    case .orb: .orb
    case .voice: .voice
    case .timer: .timer
    case .staging: .fx
    case .monitor: .monitor
    }
  }

  /// Label in the tab bar, dock, sidebar and tag.
  var title: String {
    switch self {
    case .orb: "Orb"
    case .voice: "Voz"
    case .timer: "Timer"
    case .staging: "Staging"
    case .monitor: "Monitor"
    }
  }

  var tabItem: StTabItem<ToolTab> {
    StTabItem(id: self, title: title, systemImage: tool.systemImage, tool: tool)
  }
}

struct ContentView: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var selectedTab: ToolTab = .orb
  private var settings = StSettingsStore.shared
#if os(iOS)
  @Environment(\.verticalSizeClass) private var verticalSizeClass
#endif

  private var layoutMode: StLayoutMode {
#if os(macOS)
    .mac
#elseif os(iOS)
    verticalSizeClass == .compact ? .landscape : .portrait
#else
    .portrait
#endif
  }

  /// Tab bar, dock and sidebar order, from `settings.json`.
  private var tabItems: [StTabItem<ToolTab>] {
    settings.ordered(ToolTab.allCases, id: \.rawValue).map(\.tabItem)
  }

  var body: some View {
#if os(macOS)
    HStack(spacing: 0) {
      StSidebar(tabItems, selection: $selectedTab, tool: selectedTab.tool)

      Group {
        switch selectedTab {
        case .orb: ThinkingOrbsView()
        case .voice: VoiceRingView()
        case .timer: AlarmKitView()
        case .staging: StagingView()
        case .monitor: MonitorView()
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .padding(.top, 40)
    }
    .foregroundStyle(Color.stTextPrimary)
    .background { screenBackground }
    .environment(\.stLayoutMode, layoutMode)
    .ignoresSafeArea(.container, edges: .top)
    .frame(minWidth: 1000, minHeight: 640)
#else
    TabView(selection: $selectedTab) {
      Tab(value: ToolTab.orb) {
        tabScreen { ThinkingOrbsView() }
      }

      Tab(value: ToolTab.voice) {
        tabScreen { VoiceRingView() }
      }

      Tab(value: ToolTab.timer) {
        tabScreen { AlarmKitView() }
      }

      Tab(value: ToolTab.staging) {
        tabScreen { StagingView() }
      }

      Tab(value: ToolTab.monitor) {
        tabScreen { MonitorView() }
      }
    }
    .tint(selectedTab.tool.tone)
    .environment(\.stLayoutMode, layoutMode)
    .overlay(alignment: .bottom) {
      if layoutMode == .portrait {
        StTabBar(tabItems, selection: $selectedTab)
          .ignoresSafeArea(edges: .bottom)
          .transition(.opacity)
      }
    }
    .overlay(alignment: .bottomLeading) {
      if layoutMode == .landscape {
        // Collapsed dock: safe area + 2 from the left, 16 from the bottom edge.
        StDock(tabItems, selection: $selectedTab)
          .padding(.leading, 2)
          .padding(.bottom, 16)
          .ignoresSafeArea(edges: .bottom)
          .transition(.opacity)
      }
    }
#endif
  }

  private var screenBackground: some View {
    StScreenBackground(tool: selectedTab.tool, isLandscape: layoutMode != .portrait)
      .animation(reduceMotion ? nil : .easeInOut(duration: 0.5), value: selectedTab)
  }

#if !os(macOS)
  /// One tab page: shared background, native tab bar hidden, and room at the
  /// bottom for the floating `StTabBar` in portrait. Each page draws its own
  /// background so the glow is never covered by the TabView's page background.
  private func tabScreen<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    content()
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      .foregroundStyle(Color.stTextPrimary)
      .background { screenBackground }
      .safeAreaInset(edge: .bottom, spacing: 0) {
        Color.clear.frame(height: layoutMode == .portrait ? 64 : 0)
      }
      .toolbarVisibility(.hidden, for: .tabBar)
  }
#endif
}

// MARK: - Orb

struct ThinkingOrbsView: View {
  @Environment(\.scenePhase) private var scenePhase
  @State private var currentState: OrbState = ToolSharedState.load().orbState
#if canImport(ActivityKit) && os(iOS)
  private var liveActivityManager = LiveActivityManager.shared
  @State private var liveActivityError: String?
  @State private var isChangingLiveActivity = false
#endif

  var body: some View {
    StAdaptiveToolLayout(tool: .orb, tag: ToolTab.orb.title) { size in
      StHalo(.orb, size: size) {
        ThinkingOrb(
          state: currentState,
          size: .px64,
          displaySize: size * 0.6
        )
        .contentShape(Circle())
        .onTapGesture {
          advanceState()
        }
        .accessibilityElement()
        .accessibilityLabel(currentState.label)
        .accessibilityHint("Toque para mudar o estado do orb.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { advanceState() }
      }
    } controls: {
      StToolHeader(
        title: ToolTab.orb.title,
        subtitle: headerStatus.title,
        tool: .orb,
        status: headerStatus.dot
      )

      StChipSection(
        title: "Estado do orb",
        dot: StTool.orb.secondary,
        items: OrbState.allCases,
        label: { $0.label.replacingOccurrences(of: "…", with: "") },
        color: { StAccent.color(at: OrbState.allCases.firstIndex(of: $0) ?? 0) },
        isOn: { $0 == currentState },
        select: select
      )

#if canImport(ActivityKit) && os(iOS)
      liveActivityButton
        .padding(.top, 4)
#endif
    }
    .onAppear {
      currentState = ToolSharedState.load().orbState
#if canImport(ActivityKit) && os(iOS)
      liveActivityManager.syncActiveActivity()
#endif
    }
    .task {
      for await _ in NotificationCenter.default.notifications(named: .smartiumOrbStateDidChange) {
        currentState = ToolSharedState.load().orbState
      }
    }
    .onChange(of: scenePhase) { _, newPhase in
      if newPhase == .active {
        currentState = ToolSharedState.load().orbState
#if canImport(ActivityKit) && os(iOS)
        liveActivityManager.syncActiveActivity()
#endif
      }
    }
  }

  private var headerStatus: (title: String, dot: StHeaderStatus) {
#if canImport(ActivityKit) && os(iOS)
    liveActivityManager.isRunning
      ? ("Live Activity na Ilha Dinâmica", .active)
      : ("Pronto para Live Activity", .ready)
#else
    // macOS has no island; the menu bar CTA is not implemented yet.
    (currentState.label, .configured)
#endif
  }

#if canImport(ActivityKit) && os(iOS)
  private var liveActivityButton: some View {
    let isRunning = liveActivityManager.isRunning
    return StButton(
      isRunning ? "Encerrar Live Activity" : "Ativar na Ilha Dinâmica",
      systemImage: isRunning ? "xmark" : "arrow.right",
      kind: isRunning ? .outlined(.orb, puck: .voice) : .primary(.orb),
      leadingDot: isRunning ? StTool.timer.tone : nil,
      action: toggleLiveActivity
    )
    .disabled(isChangingLiveActivity)
    .alert("Atividade ao Vivo", item: $liveActivityError) { _ in
    } message: { error in
      Text(error)
    }
  }

  private func toggleLiveActivity() {
    isChangingLiveActivity = true
    let wasRunning = liveActivityManager.isRunning
    Task {
      defer { isChangingLiveActivity = false }
      await liveActivityManager.toggle(
        toolTitle: "SmartiumTools",
        state: currentState
      )
      liveActivityError = liveActivityManager.lastErrorMessage
      // Only when this button just started the activity: leave the app so
      // the island is visible right away.
      if !wasRunning, liveActivityManager.isRunning, liveActivityError == nil {
        minimizeApp()
      }
    }
  }

  /// Sends the app to the background, like pressing Home. There is no public
  /// API for this; `suspend` is private UIKit behavior and may be rejected by
  /// App Review.
  private func minimizeApp() {
    UIApplication.shared.perform(#selector(NSXPCConnection.suspend))
  }
#endif

  /// Advances the ThinkingOrb to the next available state and syncs Widgets + Dynamic Island.
  private func advanceState() {
    let allStates = OrbState.allCases
    guard let index = allStates.firstIndex(of: currentState) else { return }
    let nextIndex = (index + 1) % allStates.count
    select(allStates[nextIndex])
  }

  /// Sets the orb state, saves it to the shared state and updates the Live Activity.
  private func select(_ state: OrbState) {
    guard state != currentState else { return }
    currentState = state

    ToolSharedState.updateOrbState(state)

#if canImport(ActivityKit) && os(iOS)
    Task {
      await liveActivityManager.update(state: state)
    }
#endif
  }
}

// MARK: - Voice

/// Voice modes (v0.2 "MODOS"). Visual placeholder only.
private enum VoiceMode: CaseIterable {
  case dictation, translation, commands, notes

  var title: String {
    switch self {
    case .dictation: "Ditado"
    case .translation: "Tradução"
    case .commands: "Comandos"
    case .notes: "Notas"
    }
  }

  var color: StRGB {
    switch self {
    case .dictation: StAccent.sky
    case .translation: StTool.timer.rgb
    case .commands: StTool.fx.rgb
    case .notes: StAccent.brand
    }
  }
}

struct VoiceRingView: View {
  @State private var mode = VoiceMode.dictation

  var body: some View {
    StAdaptiveToolLayout(tool: .voice, tag: ToolTab.voice.title) { size in
      StHalo(.voice, size: size) {
        VoiceWaveform()
          .frame(width: size * 0.28, height: size * 0.28)
          .accessibilityHidden(true)
      }
    } controls: {
      StToolHeader(
        title: ToolTab.voice.title,
        subtitle: "Em breve · reconhecimento on-device",
        tool: .voice,
        status: .ready
      )

      StChipSection(
        title: "Modos",
        dot: StTool.voice.secondary,
        items: VoiceMode.allCases,
        label: \.title,
        color: \.color,
        isOn: { $0 == mode },
        select: { mode = $0 }
      )
    }
  }
}

/// Five-bar waveform (30×30 grid), center bar in the voice secondary (Âmbar).
private struct VoiceWaveform: View {
  var body: some View {
    Canvas { context, size in
      let unit = min(size.width, size.height) / 30
      let bars: [(x: CGFloat, y1: CGFloat, y2: CGFloat)] = [
        (6, 13, 17), (10.5, 9, 21), (15, 4, 26), (19.5, 9, 21), (24, 13, 17)
      ]
      for (index, bar) in bars.enumerated() {
        var path = Path()
        path.move(to: CGPoint(x: bar.x * unit, y: bar.y1 * unit))
        path.addLine(to: CGPoint(x: bar.x * unit, y: bar.y2 * unit))
        let color = index == 2 ? StTool.voice.secondary : StTool.voice.tone
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 2.6 * unit, lineCap: .round))
      }
    }
  }
}

// MARK: - Staging

/// Camera effects (v0.2 "EFEITOS"). Selection is visual only for now.
private enum StagingEffect: CaseIterable {
  case blur, duotone, grain, glitch, neon, mono

  var title: String {
    switch self {
    case .blur: "Desfoque"
    case .duotone: "Duotone"
    case .grain: "Grão"
    case .glitch: "Glitch"
    case .neon: "Néon"
    case .mono: "Mono"
    }
  }

  var color: StRGB {
    switch self {
    case .blur: StAccent.sky
    case .duotone: StAccent.brand
    case .grain: StTool.fx.rgb
    case .glitch: StTool.timer.rgb
    case .neon: StTool.voice.rgb
    case .mono: StAccent.mono
    }
  }
}

struct StagingView: View {
  @State private var effect = StagingEffect.blur

  var body: some View {
    StAdaptiveToolLayout(tool: .fx, tag: ToolTab.staging.title) { _ in
      cameraPanel
        .overlay(alignment: .topLeading) {
          StTag(effect.title, tone: effect.color.color, tint: effect.color.color(opacity: 0.18))
            .padding(14)
        }
    } controls: {
      StToolHeader(
        title: ToolTab.staging.title,
        subtitle: "Câmera traseira",
        tool: .fx,
        status: .active
      )

      StChipSection(
        title: "Efeitos",
        dot: StTool.fx.secondary,
        items: StagingEffect.allCases,
        label: \.title,
        color: \.color,
        isOn: { $0 == effect },
        select: { effect = $0 }
      )
    }
  }

  @ViewBuilder
  private var cameraPanel: some View {
#if os(iOS)
    StagingCameraView()
#else
    StagingPlaceholder(
      title: "Câmera disponível no iOS.",
      message: "O preview da câmera traseira aparece neste painel no iPhone."
    )
#endif
  }
}

/// Camera panel shown while the preview is not running (v0.2).
struct StagingPlaceholder: View {
  let title: String
  let message: String

  var body: some View {
    let fx = StTool.fx
    let shape = RoundedRectangle(cornerRadius: StRadius.card, style: .continuous)
    VStack(spacing: 12) {
      Image(systemName: "camera.fill")
        .font(StFont.body(30, .medium))
        .foregroundStyle(fx.tone)
        .frame(width: 72, height: 72)
        .background(Circle().fill(fx.opacity(0.16)))
        .shadow(color: fx.opacity(0.35), radius: 15)
        .accessibilityHidden(true)

      Text(title)
        .font(StFont.body(20, .bold))
      Text(message)
        .font(StFont.body(14))
        .foregroundStyle(Color.stTextPrimary.opacity(0.6))
        .frame(maxWidth: 240)
    }
    .multilineTextAlignment(.center)
    .padding(20)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(
      shape.fill(
        EllipticalGradient(
          stops: [
            .init(color: fx.opacity(0.22), location: 0),
            .init(color: fx.secondaryRGB.color(opacity: 0.08), location: 0.55),
            .init(color: StRGB(hex: 0x141118).color, location: 0.85)
          ],
          center: UnitPoint(x: 0.3, y: 0.2),
          startRadiusFraction: 0,
          endRadiusFraction: 0.8
        )
      )
    )
    .overlay(shape.strokeBorder(fx.opacity(0.30), lineWidth: 1))
  }
}

#Preview {
  ContentView()
    .preferredColorScheme(.dark)
}
