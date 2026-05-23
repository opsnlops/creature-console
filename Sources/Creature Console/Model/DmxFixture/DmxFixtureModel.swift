import Common
import Foundation
import OSLog
import SwiftData

/// SwiftData model for a DMX fixture.
///
/// **IMPORTANT**: this model must stay in sync with `Common.DmxFixture`. The fixture's
/// nested children (channels, patterns, bindings) are stored as JSON-encoded `Data`
/// blobs rather than `@Relationship` graphs — the editor always works on the entire
/// fixture as a unit and the wire format is one document, so a relationship graph
/// would just add upsert complexity (see the explicit child-delete dance in
/// `CreatureImporter.upsertBatch` for the kind of pain we're avoiding).
@Model
final class DmxFixtureModel: Identifiable {

    private static let logger = Logger(
        subsystem: "io.opsnlops.CreatureConsole", category: "DmxFixtureModel")

    @Attribute(.unique) var id: DmxFixtureIdentifier = ""
    var name: String = ""
    var typeRaw: String = FixtureType.generic.rawValue
    var channelOffset: Int = 0
    var assignedUniverse: Int? = nil
    var channelsJSON: Data = Data("[]".utf8)
    var patternsJSON: Data = Data("[]".utf8)
    var bindingsJSON: Data = Data("[]".utf8)

    init(
        id: DmxFixtureIdentifier,
        name: String,
        typeRaw: String,
        channelOffset: Int,
        assignedUniverse: Int?,
        channelsJSON: Data,
        patternsJSON: Data,
        bindingsJSON: Data
    ) {
        self.id = id
        self.name = name
        self.typeRaw = typeRaw
        self.channelOffset = channelOffset
        self.assignedUniverse = assignedUniverse
        self.channelsJSON = channelsJSON
        self.patternsJSON = patternsJSON
        self.bindingsJSON = bindingsJSON
    }
}

extension DmxFixtureModel {

    convenience init(dto: Common.DmxFixture) {
        let encoder = JSONEncoder()
        // Best-effort encode — failures fall back to empty arrays so SwiftData persistence
        // doesn't crash on a transiently malformed nested object.
        let channels =
            (try? encoder.encode(dto.channels)) ?? Data("[]".utf8)
        let patterns =
            (try? encoder.encode(dto.patterns)) ?? Data("[]".utf8)
        let bindings =
            (try? encoder.encode(dto.bindings)) ?? Data("[]".utf8)

        self.init(
            id: dto.id,
            name: dto.name,
            typeRaw: dto.type.rawValue,
            channelOffset: Int(dto.channelOffset),
            assignedUniverse: dto.assignedUniverse.map { Int($0) },
            channelsJSON: channels,
            patternsJSON: patterns,
            bindingsJSON: bindings
        )
    }

    /// Convert back to the Common DTO. Decoding the blob columns can in principle fail
    /// (e.g. if the on-disk JSON predates a future model change); we surface an empty
    /// array in that case rather than crashing the UI.
    func toDTO() -> Common.DmxFixture {
        let decoder = JSONDecoder()
        let channels =
            (try? decoder.decode([FixtureChannel].self, from: channelsJSON)) ?? []
        let patterns =
            (try? decoder.decode([FixturePattern].self, from: patternsJSON)) ?? []
        let bindings =
            (try? decoder.decode([FixtureBinding].self, from: bindingsJSON)) ?? []

        return Common.DmxFixture(
            id: id,
            name: name,
            type: FixtureType(rawValue: typeRaw) ?? .generic,
            channelOffset: UInt16(clamping: channelOffset),
            assignedUniverse: assignedUniverse.map { UInt32(clamping: $0) },
            channels: channels,
            patterns: patterns,
            bindings: bindings
        )
    }

    /// Convenience for the table view — derive without round-tripping the whole DTO.
    var channelCount: Int {
        (try? JSONDecoder().decode([FixtureChannel].self, from: channelsJSON))?.count ?? 0
    }

    var patternCount: Int {
        (try? JSONDecoder().decode([FixturePattern].self, from: patternsJSON))?.count ?? 0
    }

    var bindingCount: Int {
        (try? JSONDecoder().decode([FixtureBinding].self, from: bindingsJSON))?.count ?? 0
    }

    var typeDisplay: String {
        switch FixtureType(rawValue: typeRaw) ?? .generic {
        case .light: return "Light"
        case .smokeMachine: return "Smoke Machine"
        case .fogger: return "Fogger"
        case .generic: return "Generic"
        }
    }
}
