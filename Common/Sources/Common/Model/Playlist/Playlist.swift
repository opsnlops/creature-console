import Foundation
import Logging

public final class Playlist: Identifiable, Hashable, Equatable, Codable, @unchecked Sendable {
    private let logger = Logger(label: "io.opsnlops.CreatureConsole.Playlist")
    public var id: PlaylistIdentifier
    public var name: String
    public var items: [PlaylistItem]

    public var numberOfItems: Int {
        return items.count
    }

    public enum CodingKeys: String, CodingKey {
        case id
        case name
        case items
        case numberOfItems = "number_of_items"
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(PlaylistIdentifier.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        items = try container.decode([PlaylistItem].self, forKey: .items)
        // numberOfItems is computed, no need to decode
        logger.debug("Created a new Playlist from init(from:)")
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(items, forKey: .items)
        try container.encode(numberOfItems, forKey: .numberOfItems)
    }

    public init(id: PlaylistIdentifier, name: String, items: [PlaylistItem]) {
        self.id = id
        self.name = name
        self.items = items
        logger.debug("Created a new Playlist from init()")
    }

    // hash(into:) function
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(name)
        hasher.combine(items)
    }

    // The == operator
    public static func == (lhs: Playlist, rhs: Playlist) -> Bool {
        return lhs.id == rhs.id && lhs.name == rhs.name && lhs.items == rhs.items
    }
}

extension Playlist {
    public static func mock() -> Playlist {
        let id = UUID().uuidString
        let name = "Mock Playlist"
        let items: [PlaylistItem] = [PlaylistItem.mock(), PlaylistItem.mock()]

        return Playlist(id: id, name: name, items: items)
    }
}
