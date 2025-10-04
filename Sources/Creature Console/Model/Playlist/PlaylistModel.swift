import Common
import Foundation
import SwiftData

/// SwiftData model for Playlist
///
/// **IMPORTANT**: This model must stay in sync with `Common.Playlist` DTO.
/// Any changes to fields here must be reflected in the Common package DTO and vice versa.
@Model
final class PlaylistModel: Identifiable {
    // Use playlist ID as the unique identifier
    @Attribute(.unique) var id: PlaylistIdentifier = ""
    var name: String = ""

    @Relationship(deleteRule: .cascade, inverse: \PlaylistItemModel.playlist)
    var items: [PlaylistItemModel] = []

    init(id: PlaylistIdentifier, name: String, items: [PlaylistItemModel]) {
        self.id = id
        self.name = name
        self.items = items
    }
}

extension PlaylistModel {
    // Initialize from the Common DTO
    convenience init(dto: Common.Playlist) {
        let itemModels = dto.items.map { PlaylistItemModel(dto: $0) }
        self.init(id: dto.id, name: dto.name, items: itemModels)
    }

    // Convert back to the Common DTO
    func toDTO() -> Common.Playlist {
        let itemDTOs = items.map { $0.toDTO() }
        return Common.Playlist(id: id, name: name, items: itemDTOs)
    }
}
