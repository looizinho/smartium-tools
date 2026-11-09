//
//  StBorderBeam.swift
//  SmartiumTools
//
//  A beam of light circling a card's border (handoff v0.6): a 1.5 pt angular
//  stroke in the tool color fading into its secondary, plus a blurred glow in
//  the secondary. One turn every 4.5 s; parked at 315° with Reduce Motion.
//
//  v0.9.4: no per-frame body. The gradients are drawn once, in a square
//  larger than the card, and only that square turns (a rotation transform,
//  so nothing is re-rendered or re-blurred). Fixed stroke masks cut out the
//  border and the glow.
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
    /// The beam's position, in CSS conic degrees (0° = top, clockwise).
    @State private var spin = Self.parkedAngle

    private var isRunning: Bool {
        !reduceMotion && isVisible && isActiveTab && scenePhase == .active
    }

    func body(content: Content) -> some View {
        content
            .overlay {
                beam
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .onAppear { isVisible = true }
            .onDisappear { isVisible = false }
            .onChange(of: isRunning) { _, running in
                update(running: running)
            }
    }

    /// Parks at 315° when paused; otherwise turns forever from there.
    private func update(running: Bool) {
        var park = Transaction()
        park.disablesAnimations = true
        withTransaction(park) { spin = Self.parkedAngle }
        guard running else { return }
        withAnimation(.linear(duration: Self.period).repeatForever(autoreverses: false)) {
            spin = Self.parkedAngle + 360
        }
    }

    private var beam: some View {
        ZStack {
            // Border: 1.5 pt.
            rotatingGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .clear, location: 250 / 360),
                .init(color: primary.opacity(0.9), location: 310 / 360),
                .init(color: secondary, location: 345 / 360),
                .init(color: .clear, location: 1),
            ])
            .mask {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(lineWidth: 1.5)
            }

            // Glow: 4 pt, 3 pt outside the card, blurred 6, at 55%.
            rotatingGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .clear, location: 280 / 360),
                .init(color: secondary, location: 340 / 360),
                .init(color: .clear, location: 1),
            ], margin: 12)
            .mask {
                RoundedRectangle(cornerRadius: cornerRadius + 3, style: .continuous)
                    .strokeBorder(lineWidth: 4)
                    .padding(-3)
                    .blur(radius: 6)
            }
            .opacity(0.55)
        }
    }

    /// A fixed angular gradient in a square whose side is the card's
    /// diagonal (plus `margin` on each side, for the glow outside the card),
    /// turned by `spin`. It overflows the card's frame unclipped; the mask
    /// cuts it. Only the rotation changes while it runs.
    private func rotatingGradient(stops: [Gradient.Stop], margin: CGFloat = 0) -> some View {
        GeometryReader { proxy in
            let side = (proxy.size.width * proxy.size.width + proxy.size.height * proxy.size.height).squareRoot() + margin * 2
            // AngularGradient starts at 3 o'clock; the prototype's conic gradient at 12.
            AngularGradient(
                stops: stops,
                center: .center,
                startAngle: .degrees(-90),
                endAngle: .degrees(270)
            )
            .frame(width: side, height: side)
            .rotationEffect(.degrees(spin))
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
    }
}
