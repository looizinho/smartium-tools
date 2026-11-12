//
//  SmartiumWidgetChrome.swift
//  SmartiumTools
//
//  The Orb widget's look, shared by every Home Screen widget (handoff v0.12
//  §2): the system theme ("auto-dark"), the background with the tool's glow,
//  the medium layout (plate on the left, brand, title, caption and button on
//  the right) and the small one ("Smartium" with a round button, the element,
//  a label). Compiled into the app and the widget extension; the app only
//  needs it for the Orb widget's shared file.
//

import SwiftUI
#if canImport(WidgetKit)
import WidgetKit

// MARK: - Theme

/// Colors that follow the system theme (§2.1). Rings and tool colors keep
/// their tone in both themes; only background, text and track change.
nonisolated struct StWidgetTheme: Sendable {
    let isDark: Bool

    init(_ colorScheme: ColorScheme) {
        isDark = colorScheme == .dark
    }

    /// #1A1724, text on the light background.
    static let ink = Color(red: 0.10, green: 0.09, blue: 0.14)
    /// #FAF7FF, the light background.
    static let paper = Color(red: 0.98, green: 0.97, blue: 1.00)

    var primary: Color { isDark ? .white : Self.ink }
    var secondary: Color { isDark ? .white.opacity(0.70) : Self.ink.opacity(0.62) }
    /// Ring track: it disappeared on the light background when it was fixed white.
    var track: Color { isDark ? .white.opacity(0.08) : Self.ink.opacity(0.08) }

    /// The round plate behind the medium layout's element.
    func plate(_ tone: Color) -> Color { isDark ? .white.opacity(0.05) : tone.opacity(0.07) }
    /// Capsule and round buttons.
    func button(_ tone: Color) -> Color { tone.opacity(isDark ? 0.85 : 0.90) }
}

/// v0.13 §6.2: the system material over the wallpaper instead of the flat
/// black at 92% / #FAF7FF, with the tool's radial glow from the top
/// trailing corner, much fainter: 12% (dark) / 8% (light). Text, track and
/// plate keep `StWidgetTheme`, so contrast stays known.
struct StWidgetBackground: View {
    let tone: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let isDark = colorScheme == .dark
        ZStack {
            Rectangle().fill(.thinMaterial)
            RadialGradient(
                colors: [tone.opacity(isDark ? 0.12 : 0.08), Color.clear],
                center: .topTrailing,
                startRadius: 8,
                endRadius: 160
            )
        }
    }
}

extension View {
    /// The widget's container background in the tool color (§2.1).
    func stWidgetBackground(_ tone: Color) -> some View {
        containerBackground(for: .widget) {
            StWidgetBackground(tone: tone)
        }
    }
}

// MARK: - Medium (338 × 158)

/// §2.2: a 96 pt plate with the 84 pt element on the left; on the right the
/// brand line, the title, the caption and, at the foot, the buttons.
struct StWidgetMediumLayout<Element: View, Actions: View>: View {
    let tone: Color
    let systemImage: String
    let brand: String
    let title: Text
    let caption: Text
    @ViewBuilder let element: () -> Element
    @ViewBuilder let actions: () -> Actions
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = StWidgetTheme(colorScheme)
        HStack(spacing: 16) {
            element()
                .frame(width: 84, height: 84)
                .padding(6)
                .background(Circle().fill(theme.plate(tone)))

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: systemImage)
                    Text(brand)
                }
                .font(StFont.body(12, .semibold))
                .foregroundStyle(tone)

                title
                    .font(StFont.body(17, .semibold))
                    .foregroundStyle(theme.primary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                caption
                    .font(StFont.body(11))
                    .foregroundStyle(theme.secondary)
                    .lineLimit(2)

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    actions()
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// The medium layout's main button: a 28 pt capsule in the tool color with
/// white 11 pt semibold text.
struct StWidgetCapsule: View {
    let title: LocalizedStringKey
    let systemImage: String
    let tone: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(StFont.body(11, .semibold))
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(Capsule().fill(StWidgetTheme(colorScheme).button(tone)))
            .foregroundStyle(.white)
    }
}

// MARK: - Small (158 × 158)

/// §2.3: "Smartium" and a 24 pt round button on top, the 74 pt element in
/// the middle, a 12 pt label at the foot.
struct StWidgetSmallLayout<Element: View, Corner: View>: View {
    let label: Text
    @ViewBuilder let corner: () -> Corner
    @ViewBuilder let element: () -> Element
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = StWidgetTheme(colorScheme)
        VStack(spacing: 8) {
            HStack {
                Text("Smartium")
                    .font(StFont.body(11, .bold))
                    .foregroundStyle(theme.secondary)
                Spacer()
                corner()
            }

            element()
                .frame(width: 74, height: 74)

            label
                .font(StFont.body(12, .semibold))
                .foregroundStyle(theme.primary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

/// The small layout's 24 pt round button.
struct StWidgetRoundButton: View {
    let systemImage: String
    let tone: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(StFont.body(11, .bold))
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(Circle().fill(tone))
    }
}

// MARK: - Ring

/// A progress ring on the theme's track, with content in the middle.
struct StWidgetRing<Content: View>: View {
    let fraction: Double
    let color: Color
    var lineWidth: CGFloat = 7
    @ViewBuilder let content: () -> Content
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Circle()
                .stroke(StWidgetTheme(colorScheme).track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(fraction, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            content()
                .padding(lineWidth + 3)
        }
        .padding(lineWidth / 2)
    }
}
#endif
