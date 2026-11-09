//
//  StDialRing.swift
//  SmartiumTools
//
//  Hero circles shared by the app, the widget extension and the watch app
//  (v0.10): `StDialRing` (from StMeters, handoff v0.3) and `StHalo` (from
//  StComponents, handoff v0.2). Moved here unchanged.
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
