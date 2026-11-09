//
//  StCornerLabel.swift
//  SmartiumWatch
//
//  Tool name curved around the screen's top-left corner (handoff v0.10.1),
//  like the corner complications of the Infograph face. SwiftUI has no text
//  on a path, so each glyph is drawn on its own: measured, placed by arc
//  length along the path and turned to its tangent.
//
//  The path runs 9 pt from the edges: up the left edge, around the corner on
//  an arc of radius `cornerRadius − 9`, then along the top edge. The text is
//  centered on the middle of the arc, tops facing out of the screen.
//

import SwiftUI

struct StCornerLabel: View {
    let text: String
    let color: Color
    /// Screen corner radius. Defaults to the Watch SE 3 values by width:
    /// ≈ 38 pt on 44 mm, ≈ 34 pt on 40 mm.
    var cornerRadius: CGFloat?

    static let inset: CGFloat = 9
    static let tracking: CGFloat = 1.4

    var body: some View {
        Canvas { context, size in
            let radius = max((cornerRadius ?? Self.defaultCornerRadius(width: size.width)) - Self.inset, 1)
            let glyphs = Array(text).map { character in
                context.resolve(
                    Text(String(character))
                        .font(StFont.body(12, .heavy))
                        .foregroundStyle(color)
                )
            }
            let widths = glyphs.map { $0.measure(in: size).width }
            let total = widths.reduce(0, +) + Self.tracking * CGFloat(max(glyphs.count - 1, 0))

            // Arc length 0 is the middle of the arc; glyphs go from -total/2.
            var offset = -total / 2
            for (glyph, width) in zip(glyphs, widths) {
                let (point, angle) = Self.position(at: offset + width / 2, radius: radius)
                var glyphContext = context
                glyphContext.translateBy(x: point.x, y: point.y)
                glyphContext.rotate(by: angle)
                glyphContext.draw(glyph, at: .zero, anchor: .center)
                offset += width + Self.tracking
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    static func defaultCornerRadius(width: CGFloat) -> CGFloat {
        width >= 180 ? 38 : 34
    }

    /// Point and tangent angle at arc length `s` from the middle of the arc,
    /// positive toward the top edge, negative toward the left edge.
    static func position(at s: CGFloat, radius r: CGFloat) -> (CGPoint, Angle) {
        let center = CGPoint(x: inset + r, y: inset + r)
        let halfArc = r * .pi / 4
        if s > halfArc {
            // Along the top edge, reading rightward.
            return (CGPoint(x: center.x + (s - halfArc), y: inset), .zero)
        }
        if s < -halfArc {
            // Up the left edge: tops face left, out of the screen.
            return (CGPoint(x: inset, y: center.y + (-s - halfArc)), .degrees(-90))
        }
        // On the arc: 225° (screen coordinates, y down) is its middle.
        let theta = (225 * .pi / 180) + s / r
        let point = CGPoint(x: center.x + r * cos(theta), y: center.y + r * sin(theta))
        let tangent = atan2(cos(theta), -sin(theta))
        return (point, .radians(tangent))
    }
}
