//
//  WatchRootView.swift
//  SmartiumWatch
//
//  Vertical pages (handoff v0.10 §2): the Digital Crown and a vertical drag
//  move between Voz, Timer and Monitor, in the iPhone's `tabOrder`. Opens on
//  the last page seen; a new focus from the iPhone moves to its tool.
//  v0.10.1: the circle is measured on the whole screen, almost edge to
//  edge, and the tool name curves around the top-left corner.
//

import SwiftUI

struct WatchRootView: View {
    let store: StWatchStore

    @AppStorage("watchPage") private var page = StToolDestination.timer.rawValue
    /// Tool whose tag glows, and when the glow started.
    @State private var glow: StWatchStore.FocusEvent?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TabView(selection: $page) {
            ForEach(store.state.order, id: \.self) { tool in
                WatchPage(tool: tool, store: store, glowID: glow?.tool == tool ? glow?.id : nil)
                    .tag(tool.rawValue)
            }
        }
        .tabViewStyle(.verticalPage)
        .onAppear { applyFocus(store.focusEvent, animated: false) }
        .onChange(of: store.focusEvent) { _, event in
            applyFocus(event, animated: true)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.sayHello() }
        }
        // v0.13 §5: a complication opens its own page, over the last one seen.
        .onOpenURL { url in
            guard let tool = StToolDestination(url: url),
                  store.state.order.contains(tool) else { return }
            page = tool.rawValue
        }
    }

    /// Only a new focus moves the page; a state without one leaves it alone.
    private func applyFocus(_ event: StWatchStore.FocusEvent?, animated: Bool) {
        guard let event, event != glow, store.state.order.contains(event.tool) else { return }
        glow = event
        withAnimation(animated && !reduceMotion ? .default : nil) {
            page = event.tool.rawValue
        }
    }
}

// MARK: - Page

private struct WatchPage: View {
    let tool: StToolDestination
    let store: StWatchStore
    let glowID: Date?

    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    private var style: StTool {
        switch tool {
        case .voice: .voice
        case .monitor: .monitor
        default: .timer
        }
    }

    private var title: String {
        switch tool {
        case .voice: "VOZ"
        case .monitor: "MONITOR"
        default: "TIMER"
        }
    }

    var body: some View {
        // The whole screen: the circle is centered on it, not below the bar.
        GeometryReader { proxy in
            let diameter = max(0, min(proxy.size.width - 8, proxy.size.height - 8))
            ZStack {
                content(diameter: diameter)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                WatchCornerName(title: "• " + title, tool: style, glowID: glowID)
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
        .ignoresSafeArea()
        .containerBackground(for: .tabView) {
            WatchBackground(tool: style, isDimmed: isLuminanceReduced)
        }
    }

    @ViewBuilder
    private func content(diameter: CGFloat) -> some View {
        switch tool {
        case .voice: WatchVoicePage(store: store, diameter: diameter)
        case .monitor: WatchMonitorPage(store: store, diameter: diameter)
        default: WatchTimerPage(timer: store.state.timer, diameter: diameter)
        }
    }
}

// MARK: - Chrome

/// `#0B0A0E` with a radial of the tool color at 21% from the top-left corner,
/// gone at 70%. Pure black with the screen dimmed.
private struct WatchBackground: View {
    let tool: StTool
    let isDimmed: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if isDimmed {
                    Color.black
                } else {
                    StRGB(hex: 0x0B0A0E).color
                    RadialGradient(
                        stops: [
                            .init(color: tool.opacity(0.21), location: 0),
                            .init(color: tool.opacity(0), location: 0.7)
                        ],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: max(proxy.size.width, proxy.size.height)
                    )
                }
            }
        }
        .ignoresSafeArea()
    }
}

/// The curved tool name (v0.10.1). A new focus from the iPhone makes it
/// glow white for 1.4 s; no glow with Reduce Motion. 60% with the screen dimmed.
private struct WatchCornerName: View {
    let title: String
    let tool: StTool
    let glowID: Date?

    @State private var glowOpacity = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        StCornerLabel(text: title, color: tool.tone)
            .shadow(color: .white.opacity(glowOpacity), radius: 4)
            .opacity(isLuminanceReduced ? 0.6 : 1)
            .onChange(of: glowID, initial: true) { _, id in
                guard id != nil, !reduceMotion else { return }
                glowOpacity = 1
                withAnimation(.easeOut(duration: 1.4)) { glowOpacity = 0 }
            }
    }
}
