//
//  StBigNumber.swift
//  SmartiumTools
//
//  Large numbers in Digital Dotted (handoff v0.3). The font only has digits
//  and letters, so ":", ",", ".", "-" and "%" are drawn as dots on the same
//  grid as the prototype (pitch 8/100 em, dot radius 3.5/100 em). Digits sit
//  in fixed-width cells, so the value never shifts sideways.
//

import SwiftUI

struct StBigNumber: View {
  /// Unit after the number. `.percent` is drawn in dots; any other text uses Nunito 700.
  struct Unit: ExpressibleByStringLiteral, Hashable {
    let text: String

    init(stringLiteral value: String) {
      text = value
    }

    static let percent: Unit = "%"
  }

  private let text: String
  private let unit: Unit?
  private let size: CGFloat
  private let color: Color
  private let unitColor: Color
  private let glow: Bool

  init(
    _ text: String,
    unit: Unit? = nil,
    size: CGFloat,
    color: Color = .stTextPrimary,
    unitColor: Color = Color.stTextPrimary.opacity(0.55),
    glow: Bool = false
  ) {
    var text = text
    var unit = unit
    if text.hasSuffix("%") {
      text.removeLast()
      unit = .percent
    }
    self.text = text
    self.unit = unit
    self.size = size
    self.color = color
    self.unitColor = unitColor
    self.glow = glow
  }

  init(
    value: Int,
    unit: Unit? = nil,
    size: CGFloat,
    color: Color = .stTextPrimary,
    glow: Bool = false
  ) {
    self.init(String(value), unit: unit, size: size, color: color, glow: glow)
  }

  var body: some View {
    // Equivalent of `minimumScaleFactor(0.6)` for a view that is not a single Text.
    ViewThatFits(in: .horizontal) {
      line(size)
      line(size * 0.85)
      line(size * 0.72)
      line(size * 0.6)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(text + (unit?.text ?? ""))
  }

  private func line(_ size: CGFloat) -> some View {
    HStack(alignment: .lastTextBaseline, spacing: 0) {
      HStack(spacing: 0) {
        ForEach(Array(text.enumerated()), id: \.offset) { _, character in
          glyph(character, size: size)
        }
        if unit == .percent {
          StDotGlyph(.percent, size: size, color: color)
        }
      }
      // Glyph cells are 1 em tall with the baseline at 0.75 em (ascent 750/1000).
      .alignmentGuide(.lastTextBaseline) { _ in size * 0.75 }
      .shadow(color: glow ? color : .clear, radius: glow ? size * 0.35 : 0)

      if let unit, unit != .percent {
        Text(unit.text)
          .font(StFont.body(max(11, (size * 0.42).rounded()), .bold))
          .foregroundStyle(unitColor)
          .padding(.leading, size * 0.14)
      }
    }
    .lineLimit(1)
    .fixedSize()
  }

  @ViewBuilder
  private func glyph(_ character: Character, size: CGFloat) -> some View {
    if let dots = StDotGlyph.Pattern(character) {
      StDotGlyph(dots, size: size, color: color)
    } else if character.isNumber || character.isLetter {
      Text(String(character))
        .font(.custom(StFont.numberFontName, fixedSize: size))
        .foregroundStyle(color)
        .frame(width: character.isNumber ? size * 0.513 : nil, height: size)
    } else {
      // Not in the font and no dot pattern: fall back to Nunito.
      Text(String(character))
        .font(StFont.body(size * 0.8, .bold))
        .foregroundStyle(color)
        .frame(height: size)
    }
  }
}

/// A punctuation glyph drawn as dots, in a 1 em tall cell with the baseline at 0.75 em.
struct StDotGlyph: View {
  struct Pattern: Hashable {
    /// Cell width in em.
    let width: CGFloat
    /// Dot centers in 1/100 em: x from the cell's left edge, y from the top of the 0.71 em digit box.
    let dots: [CGPoint]

    init(width: CGFloat, dots: [CGPoint]) {
      self.width = width
      self.dots = dots
    }

    init?(_ character: Character) {
      switch character {
      case ":": self = .colon
      case ",": self = .comma
      case ".": self = .period
      case "-", "−": self = .minus
      case " ": self = .space
      default: return nil
      }
    }

    /// Grid point: column and row on the 8/100 em pitch, starting at 4/100 em.
    private static func point(_ column: CGFloat, _ row: CGFloat, x: CGFloat = 0) -> CGPoint {
      CGPoint(x: x + 4 + column * 8, y: 4 + row * 8)
    }

    /// The prototype's `PCT` rows (5 × 9).
    static let percent = Pattern(
      width: 0.513,
      dots: ["11001", "11001", "00010", "00010", "00100", "01000", "01000", "10011", "10011"]
        .enumerated()
        .flatMap { row, bits in
          bits.enumerated().compactMap { column, bit in
            bit == "1" ? point(CGFloat(column), CGFloat(row), x: 6) : nil
          }
        }
    )
    static let colon = Pattern(width: 0.26, dots: [point(0, 2, x: 9), point(0, 6, x: 9)])
    static let period = Pattern(width: 0.24, dots: [point(0, 8, x: 8)])
    static let comma = Pattern(width: 0.24, dots: [point(0, 8, x: 8), point(0, 9, x: 4)])
    static let minus = Pattern(width: 0.34, dots: (0..<3).map { point(CGFloat($0), 4, x: 5) })
    static let space = Pattern(width: 0.25, dots: [])
  }

  private let pattern: Pattern
  private let size: CGFloat
  private let color: Color

  init(_ pattern: Pattern, size: CGFloat, color: Color) {
    self.pattern = pattern
    self.size = size
    self.color = color
  }

  var body: some View {
    Canvas { context, _ in
      let unit = size / 100
      // The 0.71 em digit box ends on the baseline (0.75 em from the top).
      let top = size * (0.75 - 0.71)
      let radius = 3.5 * unit
      for dot in pattern.dots {
        let center = CGPoint(x: dot.x * unit, y: top + dot.y * unit)
        context.fill(
          Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
          with: .color(color)
        )
      }
    }
    .frame(width: size * pattern.width, height: size)
    .accessibilityHidden(true)
  }
}

#Preview("StBigNumber") {
  VStack(alignment: .leading, spacing: 18) {
    StBigNumber("05:00", size: 47)
    StBigNumber("1:11:11", size: 47)
    StBigNumber(value: 42, unit: .percent, size: 40)
    StBigNumber("12,4", unit: "MB/s", size: 22)
    StBigNumber("88%", size: 22, color: StTool.timer.tone, glow: true)
  }
  .padding(24)
  .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  .background(Color.stInkBase)
  .foregroundStyle(Color.stTextPrimary)
}
