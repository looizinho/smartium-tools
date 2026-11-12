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
  case form

  var tool: StTool {
    switch self {
    case .orb: .orb
    case .voice: .voice
    case .timer: .timer
    case .staging: .fx
    case .monitor: .monitor
    case .form: .form
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
    case .form: "Formulário"
    }
  }

  var tabItem: StTabItem<ToolTab> {
    StTabItem(id: self, title: title, systemImage: tool.systemImage, tool: tool)
  }
}

struct ContentView: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase
  @State private var selectedTab: ToolTab = .orb
  /// When the last `smartium://tool/<id>` link arrived (v0.13 §5).
  @State private var deepLinkedAt: Date?
#if !os(macOS)
  /// Tabs whose screen exists; filled on first visit (v0.9.2).
  @State private var loadedTabs: Set<ToolTab> = []
#endif
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
    content
      .onAppear(perform: openPendingTool)
      .onReceive(NotificationCenter.default.publisher(for: .smartiumOpenToolRequested)) { _ in
        openPendingTool()
      }
      .onChange(of: scenePhase) { _, phase in
        if phase == .active { openPendingTool() }
      }
      // v0.8: Live Activities, widgets and the Mac timer open their own tab
      // (`smartium://tool/<id>`). An unknown id keeps the current tab.
      // v0.13 §5: the link wins over a pending tool, which is dropped so a
      // stale one can't switch the tab back on the next activation.
      .onOpenURL { url in
        guard let destination = StToolDestination(url: url),
              let tab = ToolTab(rawValue: destination.rawValue) else { return }
        _ = StLiveSurfaces.takePendingTool()
        deepLinkedAt = .now
        selectedTab = tab
      }
#if os(macOS)
      // Links reuse the open window instead of opening a new one.
      .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
#endif
  }

  /// Switches to the tab a control or widget asked for (v0.5). Right after
  /// a deep link, the link's tab stays (v0.13 §5).
  private func openPendingTool() {
    guard let destination = StLiveSurfaces.takePendingTool(),
          let tab = ToolTab(rawValue: destination.rawValue) else { return }
    if let deepLinkedAt, Date.now.timeIntervalSince(deepLinkedAt) < 2 { return }
    selectedTab = tab
  }

  @ViewBuilder
  private var content: some View {
#if os(macOS)
    HStack(spacing: 0) {
      StSidebar(tabItems, selection: $selectedTab, tool: selectedTab.tool)

      screen(for: selectedTab)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 40)
    }
    .foregroundStyle(Color.stTextPrimary)
    .background { screenBackground }
    .environment(\.stLayoutMode, layoutMode)
    .ignoresSafeArea(.container, edges: .top)
    .frame(minWidth: 1000, minHeight: 640)
#else
    // v0.9.2: own container instead of TabView. With six tabs the TabView
    // moved the 5th and 6th into UIKit's "More" navigation stack (back
    // button, swipe-back, empty list). Each screen is built on its first
    // visit and then only hidden, so its state survives.
    ZStack {
      ForEach(ToolTab.allCases, id: \.self) { tab in
        if loadedTabs.contains(tab) {
          let isActive = tab == selectedTab
          tabScreen { screen(for: tab) }
            .opacity(isActive ? 1 : 0)
            .allowsHitTesting(isActive)
            .accessibilityHidden(!isActive)
            .environment(\.stIsActiveTab, isActive)
        }
      }
    }
    // One background behind every tab (v0.9.4), as on the Mac, instead of
    // one per loaded tab.
    .background { screenBackground }
    .onChange(of: selectedTab, initial: true) { _, tab in
      loadedTabs.insert(tab)
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

  @ViewBuilder
  private func screen(for tab: ToolTab) -> some View {
    switch tab {
    case .orb: ThinkingOrbsView()
    case .voice: VoiceRingView()
    case .timer: AlarmKitView()
    case .staging: StagingView()
    case .monitor: MonitorView()
    case .form: FormView()
    }
  }

  private var screenBackground: some View {
    StScreenBackground(tool: selectedTab.tool, isLandscape: layoutMode != .portrait)
      .animation(reduceMotion ? nil : .easeInOut(duration: 0.5), value: selectedTab)
  }

#if !os(macOS)
  /// One tab page: room at the bottom for the floating `StTabBar` in
  /// portrait. The background sits once behind the container (v0.9.4).
  private func tabScreen<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    content()
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      .foregroundStyle(Color.stTextPrimary)
      .safeAreaInset(edge: .bottom, spacing: 0) {
        Color.clear.frame(height: layoutMode == .portrait ? 54 : 0)
      }
  }
#endif
}

// MARK: - Orb

struct ThinkingOrbsView: View {
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.stIsActiveTab) private var isActiveTab
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
          // Hidden iOS tab (v0.9.2): no animation clock.
          paused: !isActiveTab,
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
        toolTitle: "Orb",
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
private enum VoiceMode: String, CaseIterable {
  // Raw values go to the watch (v0.10).
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
        select: select
      )
    }
  }

  private func select(_ newMode: VoiceMode) {
    mode = newMode
#if os(iOS)
    StWatchSync.shared.voiceModeChanged(newMode.rawValue)
#endif
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
