import Foundation

/// A single spoken line in a multi-character dialog scene.
///
/// `text` may contain inline ElevenLabs audio tags like `[whispering]`, `[laughs]`,
/// `[sighs]`. The server strips them before forced alignment but feeds them to the
/// dialog model as expressive hints. `creatureId` MUST be the UUID of a creature that
/// exists on the server — there's no name/slug fallback.
///
/// **Note on `id`:** this is a client-only stable identity used for SwiftUI `ForEach`
/// and `.onMove`. It is intentionally excluded from `CodingKeys`, so it is never sent
/// over the wire and a fresh value is minted whenever a turn is decoded.
public struct DialogScriptTurn: Codable, Equatable, Hashable, Identifiable, Sendable {

    public var id: UUID = UUID()
    public var creatureId: CreatureIdentifier
    public var text: String

    enum CodingKeys: String, CodingKey {
        case creatureId = "creature_id"
        case text
    }

    public init(creatureId: CreatureIdentifier, text: String) {
        self.id = UUID()
        self.creatureId = creatureId
        self.text = text
    }
}

/// A saved, editable multi-character dialog scene.
///
/// Mirrors the server `DialogScript` (server v3.15.0+). `id`, `createdAt`, and
/// `updatedAt` are server-managed: they're stamped on create and ignored on update
/// (any values the client sends are discarded server-side).
///
/// **Timestamps are epoch milliseconds.** The server sends `created_at`/`updated_at`
/// as int64 wall-clock ms since the Unix epoch (e.g. `1748579999000`), *not* ISO-8601.
/// They're decoded as `Int64?` so the value is independent of any `JSONDecoder`
/// date strategy; use ``createdAtDate`` / ``updatedAtDate`` for a `Date`.
///
/// **IMPORTANT**: This DTO must stay in sync with `DialogScriptModel` in the GUI package.
public struct DialogScript: Codable, Equatable, Hashable, Identifiable, Sendable {

    public var id: DialogScriptIdentifier
    public var title: String
    public var notes: String
    public var turns: [DialogScriptTurn]
    public var createdAt: Int64?
    public var updatedAt: Int64?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case notes
        case turns
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public init(
        id: DialogScriptIdentifier,
        title: String,
        notes: String,
        turns: [DialogScriptTurn],
        createdAt: Int64? = nil,
        updatedAt: Int64? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.turns = turns
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(DialogScriptIdentifier.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        turns = try container.decodeIfPresent([DialogScriptTurn].self, forKey: .turns) ?? []
        createdAt = try container.decodeIfPresent(Int64.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(Int64.self, forKey: .updatedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        // Emit the id as a lowercase UUID string — the server matches ids case-sensitively
        // on lowercase (see `Animation.encode`), and `UUID.uuidString` is uppercase.
        try container.encode(id.uuidString.lowercased(), forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(notes, forKey: .notes)
        try container.encode(turns, forKey: .turns)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
    }

    /// `createdAt` as a `Date`, derived from the epoch-millisecond value.
    public var createdAtDate: Date? {
        createdAt.map { Date(timeIntervalSince1970: Double($0) / 1000.0) }
    }

    /// `updatedAt` as a `Date`, derived from the epoch-millisecond value.
    public var updatedAtDate: Date? {
        updatedAt.map { Date(timeIntervalSince1970: Double($0) / 1000.0) }
    }
}

/// Wire body for `POST`/`PUT /api/v1/animation/dialog/script[/{id}]`.
///
/// The server's upsert endpoint accepts **only** the editable fields and rejects any
/// `id` / `created_at` / `updated_at` (they're server-managed — strict parsing returns
/// "Unknown field"). So creates/updates must send just these three; the `id` for a `PUT`
/// travels in the URL path.
public struct UpsertDialogScriptRequest: Encodable, Sendable {

    public var title: String
    public var notes: String
    public var turns: [DialogScriptTurn]

    enum CodingKeys: String, CodingKey {
        case title
        case notes
        case turns
    }

    public init(title: String, notes: String, turns: [DialogScriptTurn]) {
        self.title = title
        self.notes = notes
        self.turns = turns
    }

    public init(_ script: DialogScript) {
        self.init(title: script.title, notes: script.notes, turns: script.turns)
    }
}

extension DialogScript {

    /// Creates a fresh, empty script with a client-side UUID `id`. The server stamps
    /// its own `id` on create; this local value is only used until the first save.
    public static func newEmpty() -> DialogScript {
        DialogScript(
            id: UUID(),
            title: "",
            notes: "",
            turns: []
        )
    }

    public static func mock() -> DialogScript {
        DialogScript(
            id: UUID(),
            title: "Beaky and Mango — UFO sighting",
            notes: "First draft, needs a tighter punchline",
            turns: [
                DialogScriptTurn(
                    creatureId: "e93b9a7a-1704-11ef-84b9-3b37dddeb225",
                    text: "[excited] Beaky! Beaky! You won't believe what I just saw outside!"),
                DialogScriptTurn(
                    creatureId: "4754fc0e-1706-11ef-931d-bbb95a696e2e",
                    text: "[skeptical] Mango, if this is about another squirrel, I swear..."),
            ],
            createdAt: 1_748_579_999_000,
            updatedAt: 1_748_580_015_000
        )
    }
}
