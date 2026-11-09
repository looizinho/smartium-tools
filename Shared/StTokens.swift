//
//  StTokens.swift
//  SmartiumTools
//
//  Design tokens for the SmartiumTools design system (handoff v0.1).
//  This file compiles into the app, SmartiumWidgetsExtension and the watch
//  app (`Shared/`, v0.10), so colors are defined in sRGB code instead of an
//  asset catalog.
//

import CoreText
import SwiftUI

// MARK: - Colors

nonisolated struct StRGB: Hashable, Sendable {
    let red: Double
    let green: Double
    let blue: Double

    init(hex: UInt32) {
        red = Double((hex >> 16) & 0xFF) / 255
        green = Double((hex >> 8) & 0xFF) / 255
        blue = Double(hex & 0xFF) / 255
    }

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: 1)
    }

    func color(opacity: Double) -> Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }

    /// Mixes the color with white. `amount` 0 keeps the color, 1 is white.
    func lightened(_ amount: Double) -> StRGB {
        StRGB(
            red: red + (1 - red) * amount,
            green: green + (1 - green) * amount,
            blue: blue + (1 - blue) * amount
        )
    }
}

extension Color {
    /// Brand magenta. Also chart series 2.
    nonisolated static let stBrand = StRGB(hex: 0xD12EE8).color
    /// Screen background. Also text on solid tool colors.
    nonisolated static let stInk900 = StRGB(hex: 0x0E0C12).color
    /// Card.
    nonisolated static let stInk800 = StRGB(hex: 0x17141D).color
    /// Row, well, segment track.
    nonisolated static let stInk700 = StRGB(hex: 0x211D29).color
    /// Neutral controls, bar tracks, tonal button.
    nonisolated static let stInk600 = StRGB(hex: 0x2C2735).color

    nonisolated static let stTextPrimary = StRGB(hex: 0xF6F3FA).color
    nonisolated static let stTextSecondary = StRGB(hex: 0xF6F3FA).color(opacity: 0.62)
    nonisolated static let stTextTertiary = StRGB(hex: 0xF6F3FA).color(opacity: 0.5)
    nonisolated static let stTextQuaternary = StRGB(hex: 0xF6F3FA).color(opacity: 0.4)

    /// Chart series 3 (neutral).
    nonisolated static let stSeriesNeutral = StRGB(hex: 0xF6F3FA).color(opacity: 0.55)

    /// Base under the two background radials (v0.2).
    nonisolated static let stInkBase = StRGB(hex: 0x0B0A10).color
    /// Unselected chip fill (v0.2).
    nonisolated static let stChipOff = StRGB(hex: 0x1A1720).color
    /// Collapsed dock fill (v0.2).
    nonisolated static let stDock = StRGB(hex: 0x24202C).color
}

/// Accent palette for choice components (chips, list tiles), in cycle order:
/// Íris, Magenta, Sky, Menta, Âmbar, Coral.
nonisolated enum StAccent {
    static let brand = StRGB(hex: 0xD12EE8)
    static let sky = StRGB(hex: 0x5BC8F5)
    /// Neutral chip color ("Mono").
    static let mono = StRGB(hex: 0xC9C3D3)

    static let palette: [StRGB] = [
        StTool.orb.rgb, brand, sky, StTool.timer.rgb, StTool.fx.rgb, StTool.voice.rgb
    ]

    static func color(at index: Int) -> StRGB {
        palette[((index % palette.count) + palette.count) % palette.count]
    }
}

/// One color per tool. Each tool has a solid tone, a 16% tint and a 28% glow.
nonisolated enum StTool: String, CaseIterable, Hashable, Sendable {
    /// Íris. Orb tab, chart series 1, devices.
    case orb
    /// Coral. Voice tab, "alert" status.
    case voice
    /// Menta. Timer tab, "ok" status.
    case timer
    /// Âmbar. Staging tab, "attention" status and warnings.
    case fx
    /// Sky. Monitor tab (v0.3).
    case monitor
    /// Magenta. Form tab (v0.9).
    case form

    var rgb: StRGB {
        switch self {
        case .orb: StRGB(hex: 0x8A7BFF)
        case .voice: StRGB(hex: 0xFF6B8A)
        case .timer: StRGB(hex: 0x3DDC9E)
        case .fx: StRGB(hex: 0xFFB547)
        case .monitor: StAccent.sky
        case .form: StAccent.brand
        }
    }

    /// Solid (100%). Text on top of it is always `Color.stInk900`.
    var tone: Color { rgb.color }
    /// Tint (16%): tiles, tags, ring tracks.
    var tint: Color { rgb.color(opacity: 0.16) }
    /// Glow (28%): radial screen background.
    var glow: Color { rgb.color(opacity: 0.28) }
    /// Lightened tone for text on a 22% tool fill (#B3A9FF for Íris).
    var light: Color { rgb.lightened(0.35).color }

    func opacity(_ value: Double) -> Color { rgb.color(opacity: value) }

    /// Secondary color (v0.2). The tool color stays dominant.
    var secondaryRGB: StRGB {
        switch self {
        case .orb: StAccent.brand
        case .voice: StTool.fx.rgb
        case .timer: StAccent.sky
        case .fx: StTool.voice.rgb
        case .monitor: StTool.orb.rgb
        case .form: StTool.orb.rgb
        }
    }

    var secondary: Color { secondaryRGB.color }

    /// SF Symbol for the tool (tab bar, dock, island, headers).
    var systemImage: String {
        switch self {
        case .orb: "sparkles"
        case .voice: "waveform"
        case .timer: "timer"
        case .fx: "camera.metering.spot"
        case .monitor: "gauge.with.needle"
        // Closest SF Symbol to the v0.9 clipboard (rounded sheet, three lines).
        case .form: "doc.plaintext"
        }
    }
}

/// Status levels for rings and bars: ≤60% Menta, ≤85% Âmbar, >85% Coral.
nonisolated enum StStatus: Hashable, Sendable {
    case ok
    case attention
    case alert

    init(fraction: Double) {
        if fraction <= 0.60 {
            self = .ok
        } else if fraction <= 0.85 {
            self = .attention
        } else {
            self = .alert
        }
    }

    var tool: StTool {
        switch self {
        case .ok: .timer
        case .attention: .fx
        case .alert: .voice
        }
    }

    var tone: Color { tool.tone }
    var tint: Color { tool.tint }
}

/// Chart series colors, in order: 1 Íris, 2 Magenta, 3 Neutral.
nonisolated enum StSeriesColor {
    static let colors: [Color] = [StTool.orb.tone, .stBrand, .stSeriesNeutral]

    static func color(at index: Int) -> Color {
        colors[index % colors.count]
    }
}

// MARK: - Radii

/// Corner radii. Always use `RoundedRectangle(cornerRadius:style: .continuous)`.
nonisolated enum StRadius {
    static let tile: CGFloat = 14
    static let row: CGFloat = 22
    static let card: CGFloat = 30
    static let tabBar: CGFloat = 34
}

// MARK: - Spacing

nonisolated enum StSpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let s: CGFloat = 12
    static let m: CGFloat = 16
    static let l: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32

    /// Screen side margin.
    static let screenMargin: CGFloat = 20
    /// Gap between cards.
    static let cardGap: CGFloat = 16
    /// Card inner padding.
    static let cardPadding: CGFloat = 22
}

// MARK: - Typography

/// UI typography (v0.3): Nunito (OFL), embedded as one variable font that
/// covers weights 400–800. No SF / `.rounded` text anywhere in the app.
nonisolated enum StFont {
    static let family = "Nunito"
    /// PostScript name of `DigitalDotted-Mono.otf`, used by `StBigNumber` and `bigNumber(_:)`.
    static let numberFontName = "DigitalDottedFont-Regular"

    /// UI text at a fixed size, for example `StFont.body(15, .semibold)`.
    static func body(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom(family, fixedSize: size).weight(weight)
    }

    /// Digital Dotted at a fixed size, for numbers the system draws itself, such
    /// as `Text(timerInterval:)` in the Live Activity (v0.4), where `StBigNumber`
    /// can't be used. The font has no ":", so it falls back to Nunito 200, whose
    /// dots match the digits' dots. Elsewhere, prefer `StBigNumber`.
    static func bigNumber(_ size: CGFloat) -> Font {
        let weightAxis = 0x7767_6874 // 'wght'
        let colon = CTFontDescriptorCreateWithAttributes([
            kCTFontNameAttribute: family,
            kCTFontVariationAttribute: [weightAxis: 200]
        ] as CFDictionary)
        let descriptor = CTFontDescriptorCreateWithAttributes([
            kCTFontNameAttribute: numberFontName,
            kCTFontCascadeListAttribute: [colon]
        ] as CFDictionary)
        return Font(CTFontCreateWithFontDescriptor(descriptor, size, nil))
    }
}

extension Font {
    /// PostScript name of `Arial Rounded Bold.ttf` (registered via `UIAppFonts`).
    nonisolated static let stLogoFontName = "ArialRoundedMTBold"

    /// Only for the "SmartiumTools" title.
    nonisolated static func stLogo(size: CGFloat = 30) -> Font {
        .custom(stLogoFontName, size: size)
    }

    /// Card title (for example "Working…"). Pair with `.tracking(-0.3)`.
    nonisolated static func stDisplay(size: CGFloat = 30) -> Font {
        StFont.body(size, .bold)
    }

    nonisolated static func stHeadline(size: CGFloat = 17) -> Font {
        StFont.body(size, .semibold)
    }

    /// Use uppercase text and `.tracking(1.4)`.
    nonisolated static let stTag = StFont.body(11, .bold)
}

// MARK: - Shadows

extension View {
    /// The only shadow in the system (tab bar).
    func stFloatingShadow() -> some View {
        shadow(color: .black.opacity(0.45), radius: 15, y: 10)
    }
}
