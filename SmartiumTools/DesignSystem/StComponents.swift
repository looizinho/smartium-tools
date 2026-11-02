//
//  StComponents.swift
//  SmartiumTools
//
//  Reusable St* components (handoff v0.1). Pure SwiftUI, no app-only APIs,
//  so the file compiles in the widget extension as well.
//

import SwiftUI

// MARK: - StButton

struct StButton: View {
  enum Kind {
    /// Capsule h56 in the tool color, label on the left, dark "puck" on the right.
    case primary(StTool)
    /// Capsule in `ink.600` with primary text.
    case tonal
    /// Capsule in `ink.700` with a tool-colored stroke and a tinted puck (v0.2).
    case outlined(StTool, puck: StTool)
    /// Circle in `ink.600` with only an icon.
    case icon
    /// Circle with the tool at 14% fill and 30% stroke, icon in the tool color (v0.2).
    case iconTinted(StTool)
  }
  
  private let title: LocalizedStringKey?
  private let systemImage: String
  private let kind: Kind
  private let leadingDot: Color?
  private let action: () -> Void
  
  init(
    _ title: LocalizedStringKey? = nil,
    systemImage: String,
    kind: Kind,
    leadingDot: Color? = nil,
    action: @escaping () -> Void
  ) {
    self.title = title
    self.systemImage = systemImage
    self.kind = kind
    self.leadingDot = leadingDot
    self.action = action
  }
  
  var body: some View {
    Button(action: action) {
      switch kind {
      case .primary(let tool):
        pillLabel(fill: tool.tone, text: .stInk900, puckFill: .stInk900, icon: tool.tone)
          .shadow(color: tool.opacity(0.35), radius: 12, y: 8)
      case .tonal:
        pillLabel(fill: .stInk600, text: .stTextPrimary, puckFill: .stInk700, icon: .stTextPrimary)
      case .outlined(let tool, let puck):
        pillLabel(fill: .stInk700, text: .stTextPrimary, puckFill: puck.opacity(0.16), icon: puck.tone)
          .overlay(Capsule().strokeBorder(tool.opacity(0.35), lineWidth: 1))
      case .iconTinted(let tool):
        Image(systemName: systemImage)
          .font(.system(size: 18, weight: .semibold))
          .foregroundStyle(tool.tone)
          .frame(width: 56, height: 56)
          .background(Circle().fill(tool.opacity(0.14)))
          .overlay(Circle().strokeBorder(tool.opacity(0.30), lineWidth: 1))
          .contentShape(Circle())
      case .icon:
        Image(systemName: systemImage)
          .font(.system(size: 18, weight: .semibold))
          .foregroundStyle(Color.stTextPrimary)
          .frame(width: 56, height: 56)
          .background(Circle().fill(Color.stInk600))
          .contentShape(Circle())
      }
    }
    .buttonStyle(StPressStyle())
    .accessibilityLabel(title.map { Text($0) } ?? Text(systemImage))
  }
  
  private func pillLabel(fill: Color, text: Color, puckFill: Color, icon: Color) -> some View {
    HStack(spacing: 10) {
      if let leadingDot {
        Circle()
          .fill(leadingDot)
          .frame(width: 8, height: 8)
          .shadow(color: leadingDot, radius: 4)
      }
      if let title {
        Text(title)
          .font(.stHeadline())
          .lineLimit(1)
          .minimumScaleFactor(0.8)
      }
      Spacer(minLength: 8)
      Image(systemName: systemImage)
        .font(.system(size: 16, weight: .bold))
        .foregroundStyle(icon)
        .frame(width: 44, height: 44)
        .background(Circle().fill(puckFill))
    }
    .foregroundStyle(text)
    .padding(.leading, 22)
    .padding(.trailing, 6)
    .frame(height: 56)
    .frame(maxWidth: .infinity)
    .background(Capsule().fill(fill))
    .contentShape(Capsule())
  }
}

/// Subtle press feedback shared by St buttons. Dims when disabled.
struct StPressStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    StPressBody(configuration: configuration)
  }
  
  private struct StPressBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    var body: some View {
      configuration.label
        .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
        .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.45)
        .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
    }
  }
}

// MARK: - StTag

struct StTag: View {
  private let text: String
  private let tone: Color
  private let tint: Color
  
  init(_ text: String, tool: StTool) {
    self.text = text
    self.tone = tool.tone
    self.tint = tool.tint
  }
  
  init(_ text: String, tone: Color, tint: Color) {
    self.text = text
    self.tone = tone
    self.tint = tint
  }
  
  var body: some View {
    HStack(spacing: 6) {
      Circle()
        .fill(tone)
        .frame(width: 6, height: 6)
      Text(text.uppercased())
        .font(.stTag)
        .tracking(1.4)
        .lineLimit(1)
    }
    .foregroundStyle(tone)
    .padding(.horizontal, 10)
    .frame(height: 26)
    .background(Capsule().fill(tint))
  }
}

// MARK: - StIconTile

struct StIconTile: View {
  private let systemImage: String
  private let tool: StTool
  private let size: CGFloat
  
  init(_ systemImage: String, tool: StTool, size: CGFloat = 40) {
    self.systemImage = systemImage
    self.tool = tool
    self.size = size
  }
  
  var body: some View {
    Image(systemName: systemImage)
      .font(.system(size: size * 0.48, weight: .semibold))
      .foregroundStyle(tool.tone)
      .frame(width: size, height: size)
      .background(
        RoundedRectangle(cornerRadius: StRadius.tile, style: .continuous)
          .fill(tool.tint)
      )
      .accessibilityHidden(true)
  }
}

// MARK: - StRow

struct StRow<Content: View>: View {
  private let systemImage: String
  private let tool: StTool
  private let showsChevron: Bool
  private let content: Content
  
  /// Row with a custom center (for example a `TextField`).
  init(
    systemImage: String,
    tool: StTool,
    showsChevron: Bool = false,
    @ViewBuilder content: () -> Content
  ) {
    self.systemImage = systemImage
    self.tool = tool
    self.showsChevron = showsChevron
    self.content = content()
  }
  
  var body: some View {
    HStack(spacing: 14) {
      StIconTile(systemImage, tool: tool)
      content
      if showsChevron {
        Image(systemName: "chevron.right")
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(Color.stTextQuaternary)
      }
    }
    .stRowBackground()
  }
}

extension StRow where Content == StRowText {
  /// Standard row: tile + title (17 medium) + value (15 tertiary).
  init(
    _ title: LocalizedStringKey,
    value: String? = nil,
    systemImage: String,
    tool: StTool,
    showsChevron: Bool = false
  ) {
    self.init(systemImage: systemImage, tool: tool, showsChevron: showsChevron) {
      StRowText(title: title, value: value)
    }
  }
}

struct StRowText: View {
  let title: LocalizedStringKey
  let value: String?
  
  var body: some View {
    HStack(spacing: 8) {
      Text(title)
        .font(.system(size: 17, weight: .medium))
        .foregroundStyle(Color.stTextPrimary)
        .lineLimit(1)
      Spacer(minLength: 8)
      if let value {
        Text(value)
          .font(.system(size: 15))
          .monospacedDigit()
          .foregroundStyle(Color.stTextTertiary)
          .lineLimit(1)
      }
    }
  }
}

extension View {
  /// Row surface: min height 64, radius 22, `ink.700`, padding 12/16.
  func stRowBackground(fill: Color = .stInk700) -> some View {
    padding(.leading, 12)
      .padding(.trailing, 16)
      .padding(.vertical, 12)
      .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: StRadius.row, style: .continuous)
          .fill(fill)
      )
  }
}

// MARK: - StSegment

/// Segmented selector. With `scrollable`, items size to their text and the
/// track scrolls horizontally (used for the 9 orb states).
struct StSegment<Item: Hashable>: View {
  private let items: [Item]
  @Binding private var selection: Item
  private let tool: StTool
  private let scrollable: Bool
  private let title: (Item) -> String
  
  @Namespace private var namespace
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  
  init(
    _ items: [Item],
    selection: Binding<Item>,
    tool: StTool,
    scrollable: Bool = false,
    title: @escaping (Item) -> String
  ) {
    self.items = items
    self._selection = selection
    self.tool = tool
    self.scrollable = scrollable
    self.title = title
  }
  
  var body: some View {
    Group {
      if scrollable {
        ScrollViewReader { proxy in
          ScrollView(.horizontal) {
            HStack(spacing: 2) { segments }
              .padding(4)
          }
          .scrollIndicators(.hidden)
          .onAppear { proxy.scrollTo(selection, anchor: .center) }
          .onChange(of: selection) { _, newValue in
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
              proxy.scrollTo(newValue, anchor: .center)
            }
          }
        }
      } else {
        HStack(spacing: 2) { segments }
          .padding(4)
      }
    }
    .frame(height: 44)
    .background(
      RoundedRectangle(cornerRadius: 22, style: .continuous)
        .fill(Color.stInk700)
    )
    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
  }
  
  private var segments: some View {
    ForEach(items, id: \.self) { item in
      let isSelected = item == selection
      Button {
        withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.75)) {
          selection = item
        }
      } label: {
        Text(title(item))
          .font(.system(size: 14, weight: .semibold))
          .lineLimit(1)
          .foregroundStyle(isSelected ? tool.light : Color.stTextSecondary)
          .padding(.horizontal, 14)
          .frame(maxWidth: scrollable ? nil : .infinity)
          .frame(maxHeight: .infinity)
          .background {
            if isSelected {
              RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(tool.opacity(0.22))
                .matchedGeometryEffect(id: "selection", in: namespace)
            }
          }
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .id(item)
      .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
  }
}

// MARK: - StDots

struct StDots: View {
  let count: Int
  let index: Int
  var tone: Color = .stBrand
  
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  
  var body: some View {
    HStack(spacing: 6) {
      ForEach(0..<count, id: \.self) { item in
        Capsule()
          .fill(item == index ? tone : Color.stInk600)
          .frame(width: item == index ? 26 : 8, height: 8)
      }
    }
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: index)
    .accessibilityElement()
    .accessibilityValue("\(index + 1) / \(count)")
  }
}

// MARK: - StCard

enum StCardStyle {
  /// `ink.800`.
  case plain
  /// Gradient from `tool @ strength` to `ink.800` at `stop` (0–1), top to bottom.
  case tinted(StTool, strength: Double = 0.14, stop: Double = 0.7)
}

struct StCard<Content: View>: View {
  private let style: StCardStyle
  private let padding: CGFloat
  private let spacing: CGFloat
  private let showsHighlight: Bool
  private let content: Content
  
  init(
    _ style: StCardStyle = .plain,
    padding: CGFloat = StSpacing.cardPadding,
    spacing: CGFloat = 10,
    showsHighlight: Bool = true,
    @ViewBuilder content: () -> Content
  ) {
    self.style = style
    self.padding = padding
    self.spacing = spacing
    self.showsHighlight = showsHighlight
    self.content = content()
  }
  
  var body: some View {
    VStack(alignment: .leading, spacing: spacing) {
      content
    }
    .padding(padding)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(StCardBackground(style: style, showsHighlight: showsHighlight))
  }
}

/// Card surface, usable on its own (for example behind a camera preview).
struct StCardBackground: View {
  var style: StCardStyle = .plain
  var showsHighlight = true
  
  var body: some View {
    let shape = RoundedRectangle(cornerRadius: StRadius.card, style: .continuous)
    ZStack {
      switch style {
      case .plain:
        shape.fill(Color.stInk800)
      case .tinted(let tool, let strength, let stop):
        shape.fill(
          LinearGradient(
            stops: [
              .init(color: tool.opacity(strength), location: 0),
              .init(color: .stInk800, location: stop)
            ],
            startPoint: .top,
            endPoint: .bottom
          )
        )
        .background(shape.fill(Color.stInk800))
      }
      if showsHighlight {
        // Top highlight (white 6%, 1pt) that fades out towards the sides.
        shape
          .strokeBorder(
            LinearGradient(
              stops: [
                .init(color: .white.opacity(0.06), location: 0),
                .init(color: .clear, location: 0.12)
              ],
              startPoint: .top,
              endPoint: .bottom
            ),
            lineWidth: 1
          )
      }
    }
  }
}

// MARK: - StHalo

/// Two-tone halo (v0.2): a radial of the tool color mixed with its secondary,
/// an outer ring stroked in the tool color and an inner ring in the secondary.
struct StHalo<Content: View>: View {
  private let tool: StTool
  private let size: CGFloat
  private let content: Content

  init(_ tool: StTool, size: CGFloat = 236, @ViewBuilder content: () -> Content) {
    self.tool = tool
    self.size = size
    self.content = content()
  }

  var body: some View {
    ZStack {
      // CSS: inset -6%, radial-gradient(circle at 38% 36%, tone 38%, secondary 14% 48%, clear 70%).
      Circle()
        .fill(
          RadialGradient(
            stops: [
              .init(color: tool.opacity(0.38), location: 0),
              .init(color: tool.secondaryRGB.color(opacity: 0.14), location: 0.48),
              .init(color: tool.opacity(0), location: 0.70)
            ],
            center: UnitPoint(x: 0.38, y: 0.36),
            startRadius: 0,
            endRadius: size * 1.12 * 0.62
          )
        )
        .padding(-size * 0.06)
      Circle()
        .fill(tool.opacity(0.07))
        .overlay(Circle().strokeBorder(tool.opacity(0.24), lineWidth: 1))
        .padding(size * 0.07)
      Circle()
        .fill(tool.opacity(0.11))
        .overlay(Circle().strokeBorder(tool.secondaryRGB.color(opacity: 0.30), lineWidth: 1))
        .padding(size * 0.19)
      content
    }
    .frame(width: size, height: size)
  }
}

// MARK: - Screen background

/// Two radials over `#0B0A10` (v0.2): the tool color at 30% and its secondary
/// at 20%. The centers move in landscape.
struct StScreenBackground: View {
  let tool: StTool
  var isLandscape = false

  var body: some View {
    GeometryReader { proxy in
      let size = proxy.size
      ZStack(alignment: .topLeading) {
        Color.stInkBase
        radial(
          tool.rgb, opacity: 0.30,
          radii: CGSize(width: size.width * 0.70, height: size.height * 0.50),
          center: isLandscape ? CGPoint(x: 0.22, y: 0.30) : CGPoint(x: 0.50, y: 0.08),
          in: size
        )
        radial(
          tool.secondaryRGB, opacity: 0.20,
          radii: CGSize(width: size.width * 0.60, height: size.height * 0.55),
          center: isLandscape ? CGPoint(x: 0.88, y: 0.85) : CGPoint(x: 0.85, y: 0.72),
          in: size
        )
      }
    }
    .ignoresSafeArea()
    .allowsHitTesting(false)
  }

  /// CSS `radial-gradient(rx ry at cx cy, color, transparent 70%)`.
  private func radial(_ rgb: StRGB, opacity: Double, radii: CGSize, center: CGPoint, in size: CGSize) -> some View {
    Ellipse()
      .fill(
        EllipticalGradient(
          stops: [
            .init(color: rgb.color(opacity: opacity), location: 0),
            .init(color: rgb.color(opacity: 0), location: 0.7)
          ],
          center: .center,
          startRadiusFraction: 0,
          endRadiusFraction: 0.5
        )
      )
      .frame(width: radii.width * 2, height: radii.height * 2)
      .position(x: size.width * center.x, y: size.height * center.y)
  }
}

// MARK: - StToolHeader

/// Status dot colors for `StToolHeader` subtitles.
enum StHeaderStatus {
  /// Menta: running.
  case active
  /// Âmbar: ready or waiting.
  case ready
  /// Sky: configured.
  case configured

  var color: Color {
    switch self {
    case .active: StTool.timer.tone
    case .ready: StTool.fx.tone
    case .configured: StAccent.sky.color
    }
  }
}

/// Tool card at the top of the controls panel (v0.2). Replaces `StTag` + a loose title.
struct StToolHeader: View {
  let title: String
  let subtitle: String
  let tool: StTool
  var status: StHeaderStatus = .ready

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
    HStack(spacing: 14) {
      Image(systemName: tool.systemImage)
        .font(.system(size: 24, weight: .semibold))
        .foregroundStyle(tool.tone)
        .frame(width: 54, height: 54)
        .background(Circle().fill(tool.opacity(0.20)))
        .overlay(Circle().strokeBorder(tool.opacity(0.45), lineWidth: 1))
        .shadow(color: tool.opacity(0.55), radius: 13)
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 3) {
        HStack(spacing: 8) {
          Text(title)
            .font(.system(size: 24, weight: .bold, design: .rounded))
            .foregroundStyle(Color.stTextPrimary)
          Image(systemName: "sparkles")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(tool.secondary)
            .accessibilityHidden(true)
        }
        HStack(spacing: 7) {
          Circle()
            .fill(status.color)
            .frame(width: 7, height: 7)
          Text(subtitle)
            .font(.system(size: 14))
            .foregroundStyle(Color.stTextPrimary.opacity(0.65))
            .lineLimit(1)
            .truncationMode(.tail)
        }
      }
      Spacer(minLength: 0)
    }
    .padding(.top, 14)
    .padding(.bottom, 14)
    .padding(.leading, 14)
    .padding(.trailing, 16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      shape.fill(
        LinearGradient(
          stops: [
            .init(color: tool.opacity(0.20), location: 0),
            .init(color: .white.opacity(0.03), location: 0.7)
          ],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
      )
    )
    .overlay(shape.strokeBorder(tool.opacity(0.38), lineWidth: 1))
    .accessibilityElement(children: .combine)
  }
}

// MARK: - StChip

/// Choice chip (v0.2): capsule h40 with a glowing color dot.
struct StChip: View {
  let title: String
  let color: StRGB
  let isOn: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 8) {
        Circle()
          .fill(color.color)
          .frame(width: 9, height: 9)
          .shadow(color: color.color, radius: 4)
        Text(title)
          .font(.system(size: 15, weight: .semibold))
          .lineLimit(1)
          .foregroundStyle(Color.stTextPrimary.opacity(isOn ? 1 : 0.78))
      }
      .padding(.leading, 12)
      .padding(.trailing, 14)
      .frame(height: 40)
      .background(Capsule().fill(isOn ? color.color(opacity: 0.18) : Color.stChipOff))
      .overlay(
        Capsule().strokeBorder(isOn ? color.color(opacity: 0.55) : Color.white.opacity(0.07), lineWidth: 1)
      )
      .contentShape(Capsule())
    }
    .buttonStyle(StPressStyle())
    .accessibilityAddTraits(isOn ? .isSelected : [])
  }
}

/// Section label: 12 bold, tracking 1.3, uppercase, with a 6pt dot.
struct StSectionLabel: View {
  let title: String
  let dot: Color

  var body: some View {
    HStack(spacing: 8) {
      Circle()
        .fill(dot)
        .frame(width: 6, height: 6)
      Text(title.uppercased())
        .font(.system(size: 12, weight: .bold))
        .tracking(1.3)
        .foregroundStyle(Color.stTextPrimary.opacity(0.55))
    }
    .padding(.top, 6)
    .padding(.horizontal, 4)
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityAddTraits(.isHeader)
  }
}

/// A labeled group of wrapping chips.
struct StChipSection<Item: Hashable>: View {
  let title: String
  let dot: Color
  let items: [Item]
  let label: (Item) -> String
  let color: (Item) -> StRGB
  let isOn: (Item) -> Bool
  let select: (Item) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      StSectionLabel(title: title, dot: dot)
      StFlowLayout(spacing: 8) {
        ForEach(items, id: \.self) { item in
          StChip(title: label(item), color: color(item), isOn: isOn(item)) {
            select(item)
          }
        }
      }
    }
  }
}

/// Left-aligned wrapping layout for chips.
struct StFlowLayout: Layout {
  var spacing: CGFloat = 8

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
    let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
    let width = rows.map(\.width).max() ?? 0
    return CGSize(width: proposal.width ?? width, height: height)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    var y = bounds.minY
    for row in arrange(width: bounds.width, subviews: subviews) {
      var x = bounds.minX
      for index in row.indices {
        let size = subviews[index].sizeThatFits(.unspecified)
        subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
        x += size.width + spacing
      }
      y += row.height + spacing
    }
  }

  private struct Row {
    var indices: [Int] = []
    var width: CGFloat = 0
    var height: CGFloat = 0
  }

  private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
    var rows: [Row] = []
    var current = Row()
    for index in subviews.indices {
      let size = subviews[index].sizeThatFits(.unspecified)
      let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
      if needed > width, !current.indices.isEmpty {
        rows.append(current)
        current = Row()
      }
      current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
      current.height = max(current.height, size.height)
      current.indices.append(index)
    }
    if !current.indices.isEmpty { rows.append(current) }
    return rows
  }
}

// MARK: - StTabBar

struct StTabItem<ID: Hashable>: Identifiable {
  let id: ID
  let title: String
  let systemImage: String
  let tool: StTool
}

struct StTabBar<ID: Hashable>: View {
  private let items: [StTabItem<ID>]
  @Binding private var selection: ID
  private let showsLabels: Bool
  
  @Namespace private var namespace
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  
  init(_ items: [StTabItem<ID>], selection: Binding<ID>, showsLabels: Bool = true) {
    self.items = items
    self._selection = selection
    self.showsLabels = showsLabels
  }
  
  var body: some View {
    HStack(spacing: 0) {
      ForEach(items) { item in
        tabButton(item)
      }
    }
    .padding(5)
    .frame(height: 68)
    .background {
      Capsule()
        .fill(StRGB(hex: 0x1C1923).color(opacity: 0.88))
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.08), lineWidth: 1))
        .stFloatingShadow()
    }
    .padding(.horizontal, 18)
    .padding(.bottom, 22)
  }
  
  private func tabButton(_ item: StTabItem<ID>) -> some View {
    let isSelected = item.id == selection
    return Button {
      withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.75)) {
        selection = item.id
      }
    } label: {
      VStack(spacing: 3) {
        Image(systemName: item.systemImage)
          .font(.system(size: 20, weight: .semibold))
          .frame(height: 24)
        if showsLabels {
          Text(item.title)
            .font(.stTabLabel)
            .lineLimit(1)
        }
      }
      .foregroundStyle(isSelected ? Color.stInk900 : Color.stTextPrimary.opacity(0.7))
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background {
        if isSelected {
          Capsule()
            .fill(item.tool.tone)
            .matchedGeometryEffect(id: "pill", in: namespace)
        }
      }
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(item.title)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}

// MARK: - Previews

#Preview("Componentes") {
  @Previewable @State var segment = "Working"
  @Previewable @State var tab = StTool.orb
  @Previewable @State var toggle = true
  
  ZStack(alignment: .bottom) {
    StScreenBackground(tool: tab)
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        HStack {
          ForEach(StTool.allCases, id: \.self) { tool in
            StTag(tool.rawValue, tool: tool)
          }
        }
        HStack {
          ForEach(StTool.allCases, id: \.self) { tool in
            StIconTile("sparkles", tool: tool)
          }
          StDots(count: 5, index: 2)
        }
        StButton("Ativar na Ilha Dinâmica", systemImage: "arrow.right", kind: .primary(.orb)) {}
        HStack {
          StButton("Encerrar", systemImage: "xmark", kind: .tonal, leadingDot: StTool.timer.tone) {}
          StButton(systemImage: "arrow.counterclockwise", kind: .icon) {}
        }
        StSegment(["Working", "Listening", "Idle"], selection: $segment, tool: .orb) { $0 }
        StRow("Em andamento…", value: "05:00", systemImage: "timer", tool: .timer, showsChevron: true)
        StRow(systemImage: "switch.2", tool: .fx) {
          Toggle("Alerta", isOn: $toggle)
            .tint(StTool.fx.tone)
        }
        StCard(.tinted(.voice)) {
          StTag("Voz", tool: .voice)
          Text("Em breve").font(.stDisplay()).tracking(-0.3)
        }
        StHalo(.orb) {
          Image(systemName: "sparkles")
            .font(.system(size: 64))
            .foregroundStyle(StTool.orb.tone)
        }
        .frame(maxWidth: .infinity)
      }
      .padding(20)
      .padding(.bottom, 100)
    }
    StTabBar(
      StTool.allCases.map { StTabItem(id: $0, title: $0.rawValue.capitalized, systemImage: "circle", tool: $0) },
      selection: $tab
    )
  }
  .foregroundStyle(Color.stTextPrimary)
  .preferredColorScheme(.dark)
}
