import Foundation

/// This is a bit weird. In order to mock out this class, we need to make a protocol that our implementation
/// will conform to. The mock version can implement this protocol, too, and be able to mock up a class
/// that's broken up into a bunch of files via extentions.
public protocol CreatureServerClientProtocol: AnyObject {

    func connect(serverHostname: String, serverPort: Int) throws
    func close() throws
    func getHostname() -> String
    func streamLogs(queue: BlockingThreadSafeQueue<ServerLogItem>) async
    func searchCreatures(creatureName: String) async throws -> Result<Creature, ServerError>
    func getCreature(creatureId: CreatureIdentifier) async throws -> Result<Creature, ServerError>
    func getAllCreatures() async -> Result<[Creature], ServerError>
    func createAnimation(animation: Animation) async -> Result<String, ServerError>
    func listAnimations(creatureId: CreatureIdentifier) async -> Result<
        [AnimationMetadata], ServerError
    >
    func getAnimation(animationId: PlaylistIdentifier) async -> Result<Animation, ServerError>
    func stopPlayingPlaylist(universe: UniverseIdentifier) async throws -> Result<
        String, ServerError
    >
    func getPlaylist(playistId: PlaylistIdentifier) async throws -> Result<Playlist, ServerError>
    func startPlayingPlaylist(universe: UniverseIdentifier, playlistId: PlaylistIdentifier)
        async throws -> Result<String, ServerError>
    func streamFrame(streamFrameData: StreamFrameData) async -> Result<String, ServerError>

}
