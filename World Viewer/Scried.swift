import Foundation
import WorldCore

/// Something April has picked out of the world to look at closely. The Mundane view shows it as
/// the JSON the World actually carries — the Viewer never re-imagines a record.
enum Scried: Hashable, Identifiable {
    case event(WorldEventEnvelope)
    case turn(ConversationItem, CharacterDeliveryRecord?)
    case fact(Fact)
    case timer(WorldTimer)

    var id: String {
        switch self {
        case .event(let event): "event:\(event.eventID.rawValue)"
        case .turn(let item, _): "item:\(item.itemID.rawValue)"
        case .fact(let fact): "fact:\(fact.factID.rawValue)"
        case .timer(let timer): "timer:\(timer.timerID.rawValue)"
        }
    }

    var title: String {
        switch self {
        case .event(let event): event.type.rawValue
        case .turn(let item, _): item.authorID.rawValue
        case .fact(let fact): fact.predicate
        case .timer(let timer): timer.purpose.rawValue
        }
    }

    /// The record as JSON, pretty-printed with sorted keys so two looks at the same thing read
    /// the same way.
    var mundaneJSON: String {
        let encoder = WorldJSON.makeEncoder(prettyPrinted: true)
        do {
            let data: Data
            switch self {
            case .event(let event): data = try encoder.encode(event)
            case .turn(let item, let delivery):
                data = try encoder.encode(ScriedTurn(item: item, delivery: delivery))
            case .fact(let fact): data = try encoder.encode(fact)
            case .timer(let timer): data = try encoder.encode(timer)
            }
            return String(decoding: data, as: UTF8.self)
        } catch {
            return "The record would not encode: \(error)"
        }
    }
}

private struct ScriedTurn: Encodable {
    var item: ConversationItem
    var delivery: CharacterDeliveryRecord?
}
