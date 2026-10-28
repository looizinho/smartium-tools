//
//  AppearanceSettings.swift
//  SmartiumTools
//

import Foundation
import SwiftUI

nonisolated public struct AppearanceSettings: Codable, Hashable, Sendable {
    var theme = "system"
    var accentColorName = "purple"

    enum CodingKeys: String, CodingKey {
        case theme
        case accentColorName = "accent-color"
    }

    public init() {}

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        theme = try values.decodeIfPresent(String.self, forKey: .theme) ?? "system"
        accentColorName = try values.decodeIfPresent(String.self, forKey: .accentColorName) ?? "purple"
    }

    private static let storageKey = "dev.smartium.tools.appearance"

    static func load() -> Self {
        let defaults = UserDefaults(suiteName: ToolSharedState.appGroupIdentifier) ?? .standard
        guard let data = defaults.data(forKey: storageKey),
              let settings = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return settings
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        let defaults = UserDefaults(suiteName: ToolSharedState.appGroupIdentifier) ?? .standard
        defaults.set(data, forKey: Self.storageKey)
    }
}

extension AppearanceSettings {
    var colorScheme: ColorScheme? {
        switch theme.lowercased() {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }

    var orbTheme: OrbTheme {
        switch colorScheme {
        case .dark: .dark
        case .light: .light
        default: .auto
        }
    }

    var accentColor: Color {
        switch accentColorName.lowercased() {
        case "black": .black
        case "white": .white
        case "red": .red
        case "orange": .orange
        case "yellow": .yellow
        case "green": .green
        case "mint": .mint
        case "teal": .teal
        case "cyan": .cyan
        case "blue": .blue
        case "indigo": .indigo
        case "pink": .pink
        case "brown": .brown
        case "gray", "grey": .gray
        default: .purple
        }
    }
}

extension EnvironmentValues {
    @Entry var smartiumAppearance = AppearanceSettings()
}
