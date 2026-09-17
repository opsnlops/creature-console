import Foundation
import WorldCore

/// The world's facts as an outline: kind › entity › predicate family › fact. Built fresh from
/// the facts every time they change; the branches carry counts so a glance says where the
/// world's attention is ("person 41, body 30").
enum FactTree {
    struct Node: Identifiable, Hashable {
        let id: String
        let title: String
        let symbol: String
        let depth: Int
        let count: Int
        /// The entity a kind-or-entity node stands for, for "Show …".
        let entity: EntityID?
        /// A leaf's fact.
        let fact: Fact?
        let children: [Node]?
    }

    static let symbols: [String: String] = [
        "person": "person", "character": "bird", "house": "house", "place": "mappin.and.ellipse",
        "thing": "cpu", "event": "calendar", "order": "shippingbox",
        "region": "door.left.hand.open",
    ]

    /// Facts whose subject, predicate, or value mention every word of `query`.
    static func matching(_ facts: [Fact], query: String) -> [Fact] {
        let words = query.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !words.isEmpty else { return facts }
        return facts.filter { fact in
            let haystack = "\(fact.subjectID.rawValue) \(fact.predicate) \(text(of: fact.value))"
                .lowercased()
            return words.allSatisfy { haystack.contains($0) }
        }
    }

    static func build(_ facts: [Fact]) -> [Node] {
        let byKind = Dictionary(grouping: facts) { kind(of: $0.subjectID) }
        return byKind.keys.sorted().map { kind in
            let ofKind = byKind[kind]!
            let byEntity = Dictionary(grouping: ofKind, by: \.subjectID)
            let entities = byEntity.keys.sorted { $0.rawValue < $1.rawValue }.map { entity in
                let about = byEntity[entity]!
                let byFamily = Dictionary(grouping: about) { family(of: $0.predicate) }
                let families = byFamily.keys.sorted().map { family in
                    let leaves = byFamily[family]!.sorted { $0.predicate < $1.predicate }
                        .map { fact in
                            Node(
                                id: "fact:\(fact.factID.rawValue)", title: fact.predicate,
                                symbol: "circle.fill", depth: 3, count: 1, entity: nil, fact: fact,
                                children: nil)
                        }
                    return Node(
                        id: "family:\(entity.rawValue):\(family)", title: family + ".",
                        symbol: "folder", depth: 2, count: leaves.count, entity: nil, fact: nil,
                        children: leaves)
                }
                return Node(
                    id: "entity:\(entity.rawValue)", title: slug(of: entity),
                    symbol: symbols[kind] ?? "square.dashed", depth: 1, count: about.count,
                    entity: entity, fact: nil, children: families)
            }
            return Node(
                id: "kind:\(kind)", title: kind, symbol: symbols[kind] ?? "square.dashed",
                depth: 0, count: ofKind.count, entity: nil, fact: nil, children: entities)
        }
    }

    /// The fact a leaf id stands for, anywhere in the outline.
    static func fact(inNodes nodes: [Node], id: String) -> Fact? {
        for node in nodes {
            if node.id == id { return node.fact }
            if let children = node.children, let found = fact(inNodes: children, id: id) {
                return found
            }
        }
        return nil
    }

    static func kind(of entity: EntityID) -> String {
        String(entity.rawValue.prefix { $0 != ":" })
    }

    static func slug(of entity: EntityID) -> String {
        guard let colon = entity.rawValue.firstIndex(of: ":") else { return entity.rawValue }
        return String(entity.rawValue[entity.rawValue.index(after: colon)...])
    }

    /// `presence.state` › `presence`; `memory.episode.2026-09-13.2` › `memory`.
    static func family(of predicate: String) -> String {
        String(predicate.prefix { $0 != "." })
    }

    /// A value as plain words, for searching and for a glance: strings as they are, an object's
    /// values run together.
    static func text(of value: WorldJSONValue) -> String {
        switch value {
        case .null: "null"
        case .bool(let bool): String(bool)
        case .number(let number): number.formatted()
        case .string(let string): string
        case .array(let items): items.map(text).joined(separator: " ")
        case .object(let object): object.values.map(text).joined(separator: " ")
        }
    }
}
