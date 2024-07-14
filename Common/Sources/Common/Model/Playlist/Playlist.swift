import Foundation
import Logging

public class Playlist: Identifiable, Hashable, Equatable, Codable {
    private let logger = Logger(label: "io.opsnlops.CreatureConsole.Playlist")
    public var id: PlaylistIdentifier
    public var name: String
    public var items: [PlaylistItem]

    public enum CodingKeys: String, CodingKey {
        case id
        case name
        case items
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(PlaylistIdentifier.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        items = try container.decode([PlaylistItem].self, forKey: .items)
        logger.debug("Created a new Playlist from init(from:)")
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

