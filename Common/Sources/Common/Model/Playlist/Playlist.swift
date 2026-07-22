import Foundation

/// **IMPORTANT**: This DTO must stay in sync with `PlaylistModel` in the GUI package.
/// Any changes to fields here must be reflected in PlaylistModel.swift and vice versa.
public struct Playlist: Identifiable, Hashable, Codable, Sendable {
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

    // Custom Codable: `numberOfItems` is computed (encoded for the server's benefit,
    // never decoded), so synthesis can't be used.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(PlaylistIdentifier.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        items = try container.decode([PlaylistItem].self, forKey: .items)
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
