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

extension Collection where Element == PlaylistItem {

    /// The sum of every item's weight.
    ///
    /// Accumulated in `UInt64` rather than the items' own `UInt32`: weights are bounded to
    /// ``PlaylistLimits/maximumItemWeight`` on the wire, but this also runs over locally
    /// edited playlists that haven't been validated yet, and a trap in a SwiftUI body over a
    /// typo is not an acceptable failure mode.
    public var totalWeight: UInt64 {
        reduce(UInt64(0)) { $0 + UInt64($1.weight) }
    }

    /// The fraction of playtime an item gets, `0...1`. Zero when nothing has any weight.
    public func share(of item: PlaylistItem) -> Double {
        let total = totalWeight
        guard total > 0 else { return 0 }
        return Double(item.weight) / Double(total)
    }

    /// The share of playtime an item gets, as a percentage.
    public func percentage(of item: PlaylistItem) -> Double {
        share(of: item) * 100
    }
}

extension Playlist {

    /// The sum of every item's weight. See ``Swift/Collection/totalWeight``.
    public var totalWeight: UInt64 {
        items.totalWeight
    }

    /// The share of playtime an item gets, as a percentage.
    public func percentage(of item: PlaylistItem) -> Double {
        items.percentage(of: item)
    }

    /// Whether every item is one the server will accept.
    public var isValid: Bool {
        !items.isEmpty && items.count <= PlaylistLimits.maximumItems && items.allSatisfy(\.isValid)
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
