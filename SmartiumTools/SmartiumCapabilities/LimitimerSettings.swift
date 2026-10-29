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

    enum CodingKeys: String, CodingKey {
        case endMessage = "end-message"
        case recents
    }

    public init(
        endMessage: String = LimitimerSettings.defaultEndMessage,
        recents: [LimitimerRecent] = []
    ) {
        self.endMessage = endMessage
        self.recents = Array(recents.prefix(Self.maximumRecents))
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        endMessage = try values.decodeIfPresent(String.self, forKey: .endMessage) ?? LimitimerSettings.defaultEndMessage
        recents = try values.decodeIfPresent([LimitimerRecent].self, forKey: .recents) ?? []
        recents = Array(recents.prefix(Self.maximumRecents))
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
