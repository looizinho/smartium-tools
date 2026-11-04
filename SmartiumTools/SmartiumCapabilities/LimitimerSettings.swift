import Foundation

nonisolated public struct LimitimerRecent: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var duration: TimeInterval
    public var message: String

    public init(duration: TimeInterval, message: String) {
        id = UUID()
        self.duration = duration
        self.message = message
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case duration
        case message
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        duration = try values.decodeIfPresent(TimeInterval.self, forKey: .duration) ?? 0
        message = try values.decodeIfPresent(String.self, forKey: .message) ?? ""
    }
}

nonisolated public struct LimitimerSettings: Codable, Hashable, Sendable {
    public static let maximumRecents = 3
    public static let defaultEndMessage = "Encerrado!"

    public var endMessage: String
    public var recents: [LimitimerRecent]
    /// End sound on the Mac (v0.7). The iPhone ignores it and follows the
    /// silent switch.
    public var ringer: StTimerRinger

    enum CodingKeys: String, CodingKey {
        case endMessage = "end-message"
        case recents
        case ringer
    }

    public init(
        endMessage: String = LimitimerSettings.defaultEndMessage,
        recents: [LimitimerRecent] = [],
        ringer: StTimerRinger = .system
    ) {
        self.endMessage = endMessage
        self.recents = Array(recents.prefix(Self.maximumRecents))
        self.ringer = ringer
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        endMessage = try values.decodeIfPresent(String.self, forKey: .endMessage) ?? LimitimerSettings.defaultEndMessage
        recents = try values.decodeIfPresent([LimitimerRecent].self, forKey: .recents) ?? []
        recents = Array(recents.prefix(Self.maximumRecents))
        // An unknown value (e.g. edited by hand) falls back to the system sound.
        ringer = (try? values.decodeIfPresent(StTimerRinger.self, forKey: .ringer)) ?? .system
    }

    public func removingRecent(id: LimitimerRecent.ID) -> Self {
        var settings = self
        settings.recents.removeAll { $0.id == id }
        return settings
    }

    public func withRecent(duration: TimeInterval, message: String) -> Self {
        let existing = recents.filter {
            $0.duration != duration || $0.message != message
        }
        let recent = LimitimerRecent(duration: duration, message: message)
        var settings = self
        settings.recents = Array(([recent] + existing).prefix(Self.maximumRecents))
        return settings
    }
}

/// Timer end sound on the Mac (`settings.limitimer.ringer`, handoff v0.7 §3).
nonisolated public enum StTimerRinger: String, Codable, CaseIterable, Hashable, Sendable {
    /// The notification's own sound.
    case system
    /// Short macOS sounds the app plays itself, only while it is open.
    case glass, ping, pop, submarine, tink
    case silent

    public var title: String {
        switch self {
        case .system: "Padrão do sistema"
        case .glass: "Vidro"
        case .ping: "Ping"
        case .pop: "Pop"
        case .submarine: "Submarino"
        case .tink: "Tink"
        case .silent: "Silencioso"
        }
    }

    /// macOS sound name for the app's own sounds.
    public var soundName: String? {
        switch self {
        case .glass: "Glass"
        case .ping: "Ping"
        case .pop: "Pop"
        case .submarine: "Submarine"
        case .tink: "Tink"
        case .system, .silent: nil
        }
    }
}
