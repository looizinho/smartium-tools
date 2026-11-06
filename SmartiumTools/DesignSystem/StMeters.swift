//
//  StMeters.swift
//  SmartiumTools
//
//  Generic meter components (handoff v0.3): dial ring, gauge tile, heatmap,
//  rate card, step meter and the SIM badge. No screen logic inside.
//  App-only: excluded from SmartiumWidgetsExtension.
//

import SwiftUI

// MARK: - StDialRing

/// Hero ring (SVG viewBox 100): radial halo, track + progress ring at r44,
/// dotted tick ring inside, and any content in the center.
struct StDialRing<Center: View>: View {
  private let size: CGFloat
  private let fraction: Double
  private let ringColor: Color
  private let trackColor: Color
  private let tickColor: Color
  private let lineWidth: CGFloat
  private let tickRadius: CGFloat
  private let halo: [Gradient.Stop]
  private let haloInset: CGFloat
  private let animationDuration: Double
  private let center: Center

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  /// `lineWidth` and `tickRadius` are in 1/100 of `size`; `haloInset` is a fraction of `size`.
  init(
    size: CGFloat,
    fraction: Double,
    ringColor: Color,
    trackColor: Color,
    tickColor: Color,
    lineWidth: CGFloat = 5,
    tickRadius: CGFloat = 37,
    halo: [Gradient.Stop],
    haloInset: CGFloat = 0.06,
    animationDuration: Double = 0.6,
    @ViewBuilder center: () -> Center
  ) {
    self.size = size
    self.fraction = fraction
    self.ringColor = ringColor
    self.trackColor = trackColor
    self.tickColor = tickColor
    self.lineWidth = lineWidth
    self.tickRadius = tickRadius
    self.halo = halo
    self.haloInset = haloInset
    self.animationDuration = animationDuration
    self.center = center()
  }

  var body: some View {
    let unit = size / 100
    ZStack {
      Circle()
        .fill(
          RadialGradient(
            stops: halo,
            center: .center,
            startRadius: 0,
            endRadius: size * (1 + haloInset * 2) * 0.5
          )
        )
        .padding(-size * haloInset)

      Circle()
        .stroke(trackColor, lineWidth: lineWidth * unit)
        .frame(width: 88 * unit, height: 88 * unit)

      Circle()
        .trim(from: 0, to: min(max(fraction, 0), 1))
        .stroke(ringColor, style: StrokeStyle(lineWidth: lineWidth * unit, lineCap: .round))
        .rotationEffect(.degrees(-90))
        .frame(width: 88 * unit, height: 88 * unit)
        .animation(reduceMotion ? nil : .easeInOut(duration: animationDuration), value: fraction)
        .animation(reduceMotion ? nil : .easeInOut(duration: animationDuration), value: ringColor)

      Circle()
        .stroke(
          tickColor,
          style: StrokeStyle(lineWidth: 1.6 * unit, lineCap: .round, dash: [0.1 * unit, 3.77 * unit])
        )
        .frame(width: tickRadius * 2 * unit, height: tickRadius * 2 * unit)

      center
        .frame(width: 70 * unit)
    }
    .frame(width: size, height: size)
  }
}

// MARK: - StSimBadge

/// "SIM" badge for values from the simulated provider.
struct StSimBadge: View {
  var body: some View {
    let amber = StTool.fx
    Text("SIM")
      .font(StFont.body(9, .bold))
      .tracking(1)
      .foregroundStyle(amber.tone)
      .padding(.horizontal, 6)
      .frame(height: 16)
      .background(Capsule().fill(amber.opacity(0.16)))
      .accessibilityLabel("Simulado")
  }
}

// MARK: - StGaugeTile

/// Card with a 52pt ring, label (+ SIM), percentage and subtitle. With an
/// action it is a button; `isPinned` adds the tinted fill and the pin badge.
struct StGaugeTile: View {
  let label: String
  /// 0–1.
  let value: Double
  let subtitle: String
  let color: Color
  var isSimulated = false
  var isPinned = false
  var action: (() -> Void)?

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    if let action {
      Button(action: action) { content }
        .buttonStyle(StPressStyle())
        .accessibilityAddTraits(isPinned ? .isSelected : [])
        .accessibilityHint(isPinned ? "Solta do destaque." : "Fixa no destaque.")
    } else {
      content
    }
  }

  private var content: some View {
    let shape = RoundedRectangle(cornerRadius: StRadius.row, style: .continuous)
    return HStack(spacing: 12) {
      ZStack {
        Circle()
          .stroke(.white.opacity(0.07), lineWidth: 5)
        Circle()
          .trim(from: 0, to: min(max(value, 0), 1))
          .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
          .rotationEffect(.degrees(-90))
          .animation(reduceMotion ? nil : .easeInOut(duration: 0.6), value: value)
      }
      .frame(width: 44, height: 44)
      .frame(width: 52, height: 52)

      VStack(alignment: .leading, spacing: 0) {
        HStack(spacing: 6) {
          Text(label)
            .font(StFont.body(13))
            .foregroundStyle(Color.stTextPrimary.opacity(0.6))
            .lineLimit(1)
            .fixedSize()
          if isSimulated {
            StSimBadge()
          }
        }
        StBigNumber(value: Int((value * 100).rounded()), unit: .percent, size: 22, color: .white)
          .padding(.vertical, 3)
        Text(subtitle)
          .font(StFont.body(12))
          .foregroundStyle(Color.stTextPrimary.opacity(0.5))
          .lineLimit(1)
          .minimumScaleFactor(0.8)
      }
      Spacer(minLength: 0)
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(shape.fill(isPinned ? color.opacity(0.10) : Color.stInk800))
    .overlay(shape.strokeBorder(isPinned ? color.opacity(0.50) : .white.opacity(0.05), lineWidth: 1))
    .overlay(alignment: .topTrailing) {
      if isPinned {
        Image(systemName: "pin.fill")
          .font(StFont.body(13, .semibold))
          .rotationEffect(.degrees(40))
          .foregroundStyle(color)
          .frame(width: 24, height: 24)
          .background(Circle().fill(color.opacity(0.18)))
          .padding(9)
          .accessibilityHidden(true)
      }
    }
    .contentShape(shape)
    .accessibilityElement(children: .combine)
  }
}

// MARK: - StHeatmap

/// One row per series, `cells` columns, each cell the status color at
/// `0.14 + v * 0.86` opacity. Header with a title and the overall value.
struct StHeatmap: View {
  struct Row: Identifiable {
    let name: String
    /// Oldest first, 0–1.
    let values: [Double]
    var id: String { name }
  }

  let title: String
  /// Overall value shown on the right, 0–1.
  let value: Double
  let rows: [Row]
  var cells = 30

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
    VStack(alignment: .leading, spacing: 5) {
      HStack {
        Text(title.uppercased())
          .font(StFont.body(12, .bold))
          .tracking(1.3)
          .foregroundStyle(Color.stTextPrimary.opacity(0.55))
        Spacer()
        Text("\(Int((value * 100).rounded()))%")
          .font(StFont.body(13, .semibold))
          .monospacedDigit()
          .foregroundStyle(StStatus(fraction: value).tone)
      }
      .padding(.bottom, 5)

      ForEach(rows) { row in
        HStack(spacing: 8) {
          Text(row.name)
            .font(StFont.body(11, .bold))
            .foregroundStyle(Color.stTextPrimary.opacity(0.55))
            .frame(width: 20, alignment: .leading)
          cellsCanvas(row.values)
            .frame(height: 12)
        }
      }

      HStack(spacing: 14) {
        legend(StStatus.ok.tone, "≤ 60%")
        legend(StStatus.attention.tone, "≤ 85%")
        legend(StStatus.alert.tone, "> 85%")
      }
      .padding(.top, 7)
      .padding(.leading, 28)
    }
    .padding(.top, 14)
    .padding(.horizontal, 16)
    .padding(.bottom, 12)
    .background(shape.fill(Color.stInk800))
    .overlay(shape.strokeBorder(.white.opacity(0.06), lineWidth: 1))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(title)
    .accessibilityValue("\(Int((value * 100).rounded()))%")
  }

  private func cellsCanvas(_ values: [Double]) -> some View {
    Canvas { context, size in
      let gap: CGFloat = 2
      let width = (size.width - gap * CGFloat(cells - 1)) / CGFloat(cells)
      // Right-aligned: the newest sample is always the last cell.
      let offset = cells - values.count
      for (index, value) in values.suffix(cells).enumerated() {
        let x = CGFloat(offset + index) * (width + gap)
        let rect = CGRect(x: x, y: 0, width: width, height: size.height)
        context.fill(
          Path(roundedRect: rect, cornerRadius: 3),
          with: .color(StStatus(fraction: value).tone.opacity(0.14 + value * 0.86))
        )
      }
    }
  }

  private func legend(_ color: Color, _ text: String) -> some View {
    HStack(spacing: 5) {
      RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
      Text(text)
    }
    .font(StFont.body(11, .semibold))
    .foregroundStyle(Color.stTextPrimary.opacity(0.55))
  }
}

// MARK: - StRateCard

/// Card with side-by-side rates: arrow + label, big number + unit, and a bar.
struct StRateCard: View {
  struct Item: Identifiable {
    let label: String
    let systemImage: String
    let color: Color
    let value: String
    let unit: String
    /// Bar fill, 0–1.
    let fraction: Double
    var id: String { label }
  }

  let items: [Item]

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: StRadius.row, style: .continuous)
    HStack(alignment: .top, spacing: 16) {
      ForEach(items) { item in
        VStack(alignment: .leading, spacing: 6) {
          HStack(spacing: 6) {
            Image(systemName: item.systemImage)
              .font(StFont.body(11, .bold))
              .foregroundStyle(item.color)
            Text(item.label)
              .font(StFont.body(13))
              .foregroundStyle(Color.stTextPrimary.opacity(0.6))
          }
          StBigNumber(item.value, unit: StBigNumber.Unit(stringLiteral: item.unit), size: 22)
            .padding(.vertical, 3)
          GeometryReader { proxy in
            Capsule()
              .fill(.white.opacity(0.07))
              .overlay(alignment: .leading) {
                Capsule()
                  .fill(item.color)
                  .frame(width: proxy.size.width * min(max(item.fraction, 0), 1))
                  .animation(reduceMotion ? nil : .easeInOut(duration: 0.6), value: item.fraction)
              }
          }
          .frame(height: 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.label)
        .accessibilityValue("\(item.value) \(item.unit)")
      }
    }
    .padding(.vertical, 14)
    .padding(.horizontal, 16)
    .background(shape.fill(Color.stInk800))
    .overlay(shape.strokeBorder(.white.opacity(0.05), lineWidth: 1))
  }
}

// MARK: - StStepMeter

/// Label + current level name, and one segment per level filled up to it.
struct StStepMeter: View {
  let title: String
  /// Name and color of each level, lowest first.
  let levels: [(name: String, color: Color)]
  /// Index of the current level.
  let level: Int

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: StRadius.row, style: .continuous)
    let current = levels[min(max(level, 0), levels.count - 1)]
    VStack(spacing: 10) {
      HStack {
        Text(title)
          .font(StFont.body(13))
          .foregroundStyle(Color.stTextPrimary.opacity(0.6))
        Spacer()
        Text(current.name)
          .font(StFont.body(15, .semibold))
          .foregroundStyle(current.color)
      }
      HStack(spacing: 4) {
        ForEach(levels.indices, id: \.self) { index in
          Capsule()
            .fill(index <= level ? levels[index].color : .white.opacity(0.07))
            .frame(height: 8)
        }
      }
    }
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: level)
    .padding(.vertical, 14)
    .padding(.horizontal, 16)
    .background(shape.fill(Color.stInk800))
    .overlay(shape.strokeBorder(.white.opacity(0.05), lineWidth: 1))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(title)
    .accessibilityValue(current.name)
  }
}
