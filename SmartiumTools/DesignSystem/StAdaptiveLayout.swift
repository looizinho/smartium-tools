//
//  StAdaptiveLayout.swift
//  SmartiumTools
//
//  Adaptive Hero/Controls layout, dock and sidebar (handoff v0.2).
//  App-only: excluded from SmartiumWidgetsExtension.
//

import SwiftUI

// MARK: - Layout mode

/// Where a tool screen is drawn.
enum StLayoutMode: Hashable {
  /// iPhone portrait (and regular size classes): VStack, the whole screen scrolls.
  case portrait
  /// iPhone landscape (`verticalSizeClass == .compact`): Hero left, Controls scroll.
  case landscape
  /// macOS window next to the sidebar.
  case mac

  /// Hero visual size: 236 / 290 / 400.
  var heroSize: CGFloat {
    switch self {
    case .portrait: 236
    case .landscape: 290
    case .mac: 400
    }
  }

  var logoSize: CGFloat {
    self == .portrait ? 30 : 24
  }
}

extension EnvironmentValues {
  @Entry var stLayoutMode: StLayoutMode = .portrait
}

// MARK: - App header

/// Logo "Smartium" + "Tools" in the tool color, and the tool tag.
struct StAppHeader: View {
  let tool: StTool
  let tag: String
  var logoSize: CGFloat = 30

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    HStack(spacing: 12) {
      Text("Smartium\(Text("Tools").foregroundStyle(tool.tone))")
        .font(.stLogo(size: logoSize))
        .foregroundStyle(Color.stTextPrimary)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: tool)
        .accessibilityAddTraits(.isHeader)

      Spacer(minLength: 8)

      StTag(tag, tool: tool)
    }
  }
}

// MARK: - Adaptive tool layout

/// One content definition per screen, arranged as Hero + Controls for the
/// current `stLayoutMode`. `hero` receives the hero size.
struct StAdaptiveToolLayout<Hero: View, Controls: View>: View {
  let tool: StTool
  let tag: String
  private let hero: (CGFloat) -> Hero
  private let controls: Controls

  @Environment(\.stLayoutMode) private var mode

  init(
    tool: StTool,
    tag: String,
    @ViewBuilder hero: @escaping (CGFloat) -> Hero,
    @ViewBuilder controls: () -> Controls
  ) {
    self.tool = tool
    self.tag = tag
    self.hero = hero
    self.controls = controls()
  }

  var body: some View {
    switch mode {
    case .portrait:
      ScrollView {
        VStack(spacing: 14) {
          hero(mode.heroSize)
            .frame(maxWidth: .infinity)
            .frame(height: mode.heroSize + 26)
          controlsStack
        }
        .padding(.top, 4)
        .padding(.horizontal, StSpacing.screenMargin)
        .padding(.bottom, 24)
      }
      .scrollBounceBehavior(.basedOnSize)
      .scrollDismissesKeyboard(.interactively)
      .safeAreaInset(edge: .top, spacing: 0) {
        stickyHeader(top: 8)
          .padding(.horizontal, StSpacing.screenMargin)
      }

    case .landscape:
      HStack(alignment: .top, spacing: 22) {
        hero(mode.heroSize)
          .frame(width: 300)
          .frame(maxHeight: .infinity)
        ScrollView {
          controlsStack
            .padding(.top, 2)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .top, spacing: 0) {
          stickyHeader(top: 4)
        }
      }
      .padding(.top, 16)

    case .mac:
      HStack(spacing: 24) {
        hero(mode.heroSize)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
              .fill(.white.opacity(0.025))
          )
        ScrollView {
          controlsStack
            .padding(.bottom, 8)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: 380)
      }
      .padding(24)
    }
  }

  /// Header that stays at the top while the content scrolls under it (v0.3):
  /// `#0B0A10 @55%` over a blur, bleeding 20pt past the sides.
  private func stickyHeader(top: CGFloat) -> some View {
    StAppHeader(tool: tool, tag: tag, logoSize: mode.logoSize)
      .padding(.top, top)
      .padding(.bottom, 10)
      .background {
        Rectangle()
          .fill(Color.stInkBase.opacity(0.55))
          .background(.ultraThinMaterial)
          .padding(.horizontal, -StSpacing.screenMargin)
          .ignoresSafeArea(edges: .top)
      }
  }

  private var controlsStack: some View {
    VStack(spacing: 12) {
      controls
    }
    .frame(maxWidth: .infinity, alignment: .top)
  }
}

// MARK: - Dock (iPhone landscape)

/// Collapsed dock: one circle with the current tab. Tap expands to all tabs;
/// selecting a tab or 7 s without interaction collapses it again.
struct StDock<ID: Hashable>: View {
  private let items: [StTabItem<ID>]
  @Binding private var selection: ID

  @State private var isExpanded = false
  @State private var collapseTask: Task<Void, Never>?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  init(_ items: [StTabItem<ID>], selection: Binding<ID>) {
    self.items = items
    self._selection = selection
  }

  private var current: StTabItem<ID>? {
    items.first { $0.id == selection }
  }

  var body: some View {
    HStack(spacing: 4) {
      if isExpanded {
        ForEach(items) { item in
          dockButton(item)
            .transition(.opacity)
        }
      } else if let current {
        Button {
          expand()
        } label: {
          Image(systemName: current.systemImage)
            .font(StFont.body(22, .semibold))
            .foregroundStyle(current.tool.tone)
            .frame(width: 48, height: 48)
            .background(Circle().fill(current.tool.opacity(0.18)))
            .contentShape(Circle())
        }
        .buttonStyle(StPressStyle())
        .accessibilityLabel(current.title)
        .accessibilityHint("Mostra todas as ferramentas.")
        .transition(.opacity)
      }
    }
    .padding(6)
    .frame(height: 60)
    .background {
      Capsule()
        .fill(Color.stDock.opacity(0.92))
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1))
        .stFloatingShadow()
    }
    .onDisappear {
      collapseTask?.cancel()
      isExpanded = false
    }
  }

  private func dockButton(_ item: StTabItem<ID>) -> some View {
    let isSelected = item.id == selection
    return Button {
      collapseTask?.cancel()
      selection = item.id
      setExpanded(false)
    } label: {
      Image(systemName: item.systemImage)
        .font(StFont.body(22, .semibold))
        .foregroundStyle(isSelected ? Color.stInk900 : item.tool.tone)
        .frame(width: 48, height: 48)
        .background(Circle().fill(isSelected ? item.tool.tone : .clear))
        .contentShape(Circle())
    }
    .buttonStyle(StPressStyle())
    .accessibilityLabel(item.title)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

  private func expand() {
    setExpanded(true)
    collapseTask?.cancel()
    collapseTask = Task {
      try? await Task.sleep(for: .seconds(7))
      guard !Task.isCancelled else { return }
      setExpanded(false)
    }
  }

  private func setExpanded(_ value: Bool) {
    withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.4, dampingFraction: 0.75)) {
      isExpanded = value
    }
  }
}

// MARK: - Sidebar (macOS)

struct StSidebar<ID: Hashable>: View {
  private let items: [StTabItem<ID>]
  @Binding private var selection: ID
  private let tool: StTool

  init(_ items: [StTabItem<ID>], selection: Binding<ID>, tool: StTool) {
    self.items = items
    self._selection = selection
    self.tool = tool
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("Smartium\(Text("Tools").foregroundStyle(tool.tone))")
        .font(.stLogo(size: 22))
        .foregroundStyle(Color.stTextPrimary)
        .padding(.horizontal, 10)
        .padding(.bottom, 18)
        .accessibilityAddTraits(.isHeader)

      ForEach(items) { item in
        row(item)
      }

      Spacer(minLength: 0)
    }
    .padding(.top, 64)
    .padding(.horizontal, 14)
    .padding(.bottom, 18)
    .frame(width: 232, alignment: .leading)
    .frame(maxHeight: .infinity, alignment: .top)
    .background(StRGB(hex: 0x0A090D).color(opacity: 0.72))
    .overlay(alignment: .trailing) {
      Rectangle()
        .fill(.white.opacity(0.06))
        .frame(width: 1)
    }
  }

  private func row(_ item: StTabItem<ID>) -> some View {
    let isSelected = item.id == selection
    return Button {
      selection = item.id
    } label: {
      HStack(spacing: 12) {
        Image(systemName: item.systemImage)
          .font(StFont.body(16, .semibold))
          .foregroundStyle(item.tool.tone)
          .frame(width: 32, height: 32)
          .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
              .fill(item.tool.opacity(0.18))
          )
        Text(item.title)
          .font(StFont.body(15, .semibold))
          .foregroundStyle(Color.stTextPrimary.opacity(isSelected ? 1 : 0.7))
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 8)
      .frame(height: 48)
      .background(
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .fill(isSelected ? item.tool.opacity(0.14) : .clear)
      )
      .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}
