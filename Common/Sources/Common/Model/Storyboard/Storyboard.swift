import Foundation

/// A saved storyboard — a HyperCard-style card of programmable tiles for operating animatronics
/// discreetly during a live show. Mirrors `DialogScript`: `id`/`createdAt`/`updatedAt` are
/// server-managed; timestamps are int64 epoch milliseconds (decoder-strategy independent).
///
/// **IMPORTANT**: keep in sync with `StoryboardModel` in the GUI package.
public struct Storyboard: Codable, Equatable, Hashable, Identifiable, Sendable {

    public var id: StoryboardIdentifier
    public var title: String
    public var notes: String
    public var tiles: [StoryboardTile]
    public var createdAt: Int64?
    public var updatedAt: Int64?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case notes
        case tiles
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public init(
        id: StoryboardIdentifier,
        title: String,
        notes: String,
        tiles: [StoryboardTile],
        createdAt: Int64? = nil,
        updatedAt: Int64? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.tiles = tiles
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(StoryboardIdentifier.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        tiles = try container.decodeIfPresent([StoryboardTile].self, forKey: .tiles) ?? []
        createdAt = try container.decodeIfPresent(Int64.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(Int64.self, forKey: .updatedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        // Emit the id as a lowercase UUID string — the server matches ids case-sensitively.
        try container.encode(id.uuidString.lowercased(), forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(notes, forKey: .notes)
        try container.encode(tiles, forKey: .tiles)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
    }

    public var createdAtDate: Date? {
        createdAt.map { Date(timeIntervalSince1970: Double($0) / 1000.0) }
    }
    public var updatedAtDate: Date? {
        updatedAt.map { Date(timeIntervalSince1970: Double($0) / 1000.0) }
    }
}

/// Wire body for `POST`/`PUT /api/v1/storyboard[/{id}]` — only the editable fields. The server
/// stamps/owns `id`/`created_at`/`updated_at`; the `id` for a `PUT` travels in the URL path.
public struct UpsertStoryboardRequest: Encodable, Sendable {

    public var title: String
    public var notes: String
    public var tiles: [StoryboardTile]

    enum CodingKeys: String, CodingKey {
        case title, notes, tiles
    }

    public init(title: String, notes: String, tiles: [StoryboardTile]) {
        self.title = title
        self.notes = notes
        self.tiles = tiles
    }

    public init(_ storyboard: Storyboard) {
        self.init(title: storyboard.title, notes: storyboard.notes, tiles: storyboard.tiles)
    }
}

extension Storyboard {

    /// A fresh, empty card with a client-side UUID `id` (the server stamps its own on create).
    public static func newEmpty() -> Storyboard {
        Storyboard(id: UUID(), title: "", notes: "", tiles: [])
    }

    public static func mock() -> Storyboard {
        Storyboard(
            id: UUID(),
            title: "Front Porch",
            notes: "Greet + heckle.",
            tiles: [
                StoryboardTile(
                    x: 0.06, y: 0.08, width: 0.26, height: 0.20, label: "Greet",
                    sfSymbol: "hand.wave.fill", tintColorHex: "#34C759",
                    action: .adHocSpeech(
                        creatureId: "e93b9a7a-1704-11ef-84b9-3b37dddeb225", resumePlaylist: true)),
                StoryboardTile(
                    x: 0.40, y: 0.08, width: 0.26, height: 0.20, label: "Live: Mango",
                    sfSymbol: "gamecontroller.fill", tintColorHex: "#0A84FF",
                    action: .liveControl(
                        creatureId: "4754fc0e-1706-11ef-931d-bbb95a696e2e", universe: 2)),
            ],
            createdAt: 1_748_579_999_000,
            updatedAt: 1_748_580_015_000
        )
    }
}
