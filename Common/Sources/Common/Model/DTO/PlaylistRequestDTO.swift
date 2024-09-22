import Foundation

public struct PlaylistRequestDTO: Codable {
    public var playlist_id: PlaylistIdentifier
    public var universe: UniverseIdentifier
}
