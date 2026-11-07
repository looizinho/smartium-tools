//
//  StBorderBeam.swift
//  SmartiumTools
//
//  A beam of light circling a card's border (handoff v0.6): a 1.5 pt angular
//  stroke in the tool color fading into its secondary, plus a blurred glow in
//  the secondary. One turn every 4.5 s; parked at 315° with Reduce Motion.
//

import SwiftUI

extension EnvironmentValues {
    /// False on an iOS tab that is loaded but hidden (v0.9.2): animations,
    /// sampling and the camera pause there. Always true elsewhere.
    @Entry var stIsActiveTab = true
}

extension View {
    /// Adds the border beam over the card's existing stroke.
    func stBorderBeam(primary: Color, secondary: Color, cornerRadius: CGFloat = 28) -> some View {
        modifier(StBorderBeam(primary: primary, secondary: secondary, cornerRadius: cornerRadius))
    }

    /// Border beam in a tool's color pair.
    func stBorderBeam(_ tool: StTool, cornerRadius: CGFloat = 28) -> some View {
        stBorderBeam(primary: tool.tone, secondary: tool.secondary, cornerRadius: cornerRadius)
    }
}

private struct StBorderBeam: ViewModifier {
    static let period: TimeInterval = 4.5
    static let parkedAngle: Double = 315

    let primary: Color
    let secondary: Color
    let cornerRadius: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.stIsActiveTab) private var isActiveTab
    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .overlay {
                TimelineView(.animation(paused: reduceMotion || !isVisible || !isActiveTab || scenePhase != .active)) { context in
                    beam(angle: angle(at: context.date))
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .onAppear { isVisible = true }
            .onDisappear { isVisible = false }
    }

    /// The beam's position, in CSS conic degrees (0° = top, clockwise).
    private func angle(at date: Date) -> Double {
        guard !reduceMotion else { return Self.parkedAngle }
        let progress = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Self.period) / Self.period
        return progress * 360
    }

    private func beam(angle: Double) -> some View {
        // AngularGradient starts at 3 o'clock; the prototype's conic gradient at 12.
        let start = Angle.degrees(angle - 90)
        return ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    AngularGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .clear, location: 250 / 360),
                            .init(color: primary.opacity(0.9), location: 310 / 360),
                            .init(color: secondary, location: 345 / 360),
                            .init(color: .clear, location: 1),
                        ],
                        center: .center,
                        startAngle: start,
                        endAngle: start + .degrees(360)
                    ),
                    lineWidth: 1.5
                )
            RoundedRectangle(cornerRadius: cornerRadius + 3, style: .continuous)
                .strokeBorder(
                    AngularGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .clear, location: 280 / 360),
                            .init(color: secondary, location: 340 / 360),
                            .init(color: .clear, location: 1),
                        ],
                        center: .center,
                        startAngle: start,
                        endAngle: start + .degrees(360)
                    ),
                    lineWidth: 4
                )
                .padding(-3)
                .blur(radius: 6)
                .opacity(0.55)
        }
    }
}
