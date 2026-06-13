import Foundation
import MongoKitten

/// A single entity that a piece of content (a storyboard or a dialog script) points at.
/// These are discovered by scanning the document for the known reference keys; the content
/// itself is stored verbatim/opaque, so extraction is always best-effort.
public struct EntityReference: Equatable, Hashable, Sendable {

    public enum Kind: String, Sendable, CaseIterable {
        case animation
        case creature
        case playlist
        case dialogScript
        case fixture
        case sound

        /// The destination collection that stores this kind of entity, or `nil` if it
        /// isn't stored in the database at all (sounds are files on disk, keyed by name).
        public var collection: String? {
            switch self {
            case .animation: return "animations"
            case .creature: return "creatures"
            case .playlist: return "playlists"
            case .dialogScript: return "dialog_scripts"
            case .fixture: return "fixtures"
            case .sound: return nil
            }
        }

        /// Human-readable singular label for messages.
        public var label: String {
            switch self {
            case .animation: return "animation"
            case .creature: return "creature"
            case .playlist: return "playlist"
            case .dialogScript: return "dialog script"
            case .fixture: return "fixture"
            case .sound: return "sound"
            }
        }
    }

    /// What kind of entity this references.
    public let kind: Kind
    /// The UUID the reference points at (or, for sounds, the file name).
    public let identifier: String
    /// Where the reference was found (a storyboard action `type`, or "dialog turn").
    public let origin: String

    public init(kind: Kind, identifier: String, origin: String) {
        self.kind = kind
        self.identifier = identifier
        self.origin = origin
    }
}

/// Extracts entity references from reference-bearing content. Everything here is read
/// defensively — any unexpected shape is skipped rather than treated as an error.
public enum ContentReferences {

    /// Storyboard tile-action key → referenced entity kind. Mirrors the action `type`
    /// reference table in `docs/storyboard-server-contract.md`.
    static let storyboardActionKeys: [(key: String, kind: EntityReference.Kind)] = [
        ("animation_id", .animation),
        ("creature_id", .creature),
        ("playlist_id", .playlist),
        ("script_id", .dialogScript),
        ("fixture_id", .fixture),
        ("file_name", .sound),
    ]

    /// Returns every reference contained in a document from the given collection, in
    /// document order. Collections that don't reference anything return an empty array.
    public static func references(in document: Document, collection: String) -> [EntityReference] {
        switch collection {
        case "storyboards": return storyboardReferences(in: document)
        case "dialog_scripts": return dialogScriptReferences(in: document)
        default: return []
        }
    }

    /// Storyboard references live in each tile's opaque `action` object.
    private static func storyboardReferences(in storyboard: Document) -> [EntityReference] {
        guard let tiles = storyboard["tiles"] as? Document else { return [] }

        var result: [EntityReference] = []
        for tileValue in tiles.values {
            guard let tile = tileValue as? Document,
                let action = tile["action"] as? Document
            else { continue }

            let origin = (action["type"] as? String) ?? "unknown"
            for (key, kind) in storyboardActionKeys {
                if let identifier = action[key] as? String, !identifier.isEmpty {
                    result.append(
                        EntityReference(kind: kind, identifier: identifier, origin: origin))
                }
            }
        }
        return result
    }

    /// A dialog script references the creature speaking each of its turns.
    private static func dialogScriptReferences(in script: Document) -> [EntityReference] {
        guard let turns = script["turns"] as? Document else { return [] }

        var result: [EntityReference] = []
        for turnValue in turns.values {
            guard let turn = turnValue as? Document,
                let creatureId = turn["creature_id"] as? String, !creatureId.isEmpty
            else { continue }
            result.append(
                EntityReference(kind: .creature, identifier: creatureId, origin: "dialog turn"))
        }
        return result
    }
}
