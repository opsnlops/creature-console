
import Foundation



/**
 This is a bit weird. In order to mock out this class, we need to make a protocol that our implementation
 will conform to. The mock version can implement this protocol, too, and be able to mock up a class
 that's broken up into a bunch of files via extentions.
 */
protocol CreatureServerClientProtocol: AnyObject {

    func connect(serverHostname: String, serverPort: Int) throws
    func close() throws
    func getHostname() -> String
    func streamLogs(queue: BlockingThreadSafeQueue<ServerLogItem>) async
    func streamJoystick(joystick: Joystick, creature: Creature, universe: UInt32) async throws
    func searchCreatures(creatureName: String) async throws -> Result<Creature, ServerError>
    func getCreature(creatureId: Data) async throws -> Result<Creature, ServerError>
    func getAllCreatures() async -> Result<[Creature], ServerError>
    func createAnimation(animation: Animation) async -> Result<String, ServerError>
    func listAnimations(creature: Creature) async -> Result<[AnimationMetadata], ServerError>
    func getAnimation(animationId: Data) async -> Result<Animation, ServerError>
    func stopPlayingPlayist(universe: UInt32) async throws -> Result<String, ServerError>
    func getPlaylist(playistId: Data) async throws -> Result<Playlist, ServerError>
    func startPlayingPlaylist(universe: UInt32, playlistId: Data) async throws -> Result<String, ServerError>

}
