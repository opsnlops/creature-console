import Common
import Foundation
import SwiftData

/// SwiftData model for PlaylistItem
///
/// **IMPORTANT**: This model must stay in sync with `Common.PlaylistItem` DTO.
/// Any changes to fields here must be reflected in the Common package DTO and vice versa.
@Model
final class PlaylistItemModel {
    var animationId: String = ""
    var weight: UInt32 = 0

    // Inverse relationship back to the playlist that owns this item
    var playlist: PlaylistModel?

    init(animationId: String, weight: UInt32) {
        self.animationId = animationId
        self.weight = weight
    }
}

extension PlaylistItemModel {
    // Initialize from the Common DTO
    convenience init(dto: Common.PlaylistItem) {
        self.init(animationId: dto.animationId, weight: dto.weight)
    }

    // Convert back to the Common DTO
    func toDTO() -> Common.PlaylistItem {
        Common.PlaylistItem(animationId: animationId, weight: weight)
    }
}
