
import Foundation
import GRPC
import NIOCore
import NIOPosix
import OSLog
import SwiftUI
import SwiftProtobuf


/**
 This is a bit weird. In order to mock out this class, we need to make a protocol that our implementation
 will conform to. The mock version can implement this protocol, too, and be able to mock up a class
 that's broken up into a bunch of files via extentions.
 */
protocol CreatureServerClientProtocol: AnyObject {
    var appState : AppState? { get set }
    var audioManager : AudioManager? { get set }
    
    func connect(serverHostname: String, serverPort: Int) throws
    func close() throws
    func getHostname() -> String
    func streamLogs(logViewModel: LogViewModel, logFilter: Server_LogFilter, stopFlag: StopFlag) async
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



class CreatureServerClient : CreatureServerClientProtocol, ObservableObject {
    static let shared = CreatureServerClient()
    
    var appState : AppState?
    
    // Audio stuff
    var audioManager : AudioManager?
    @AppStorage("audioFilePath") var audioFilePath: String = ""
    
    @AppStorage("useOurJoystick") private var useOurJoystick: Bool = true
    
    @AppStorage("activeUniverse") var activeUniverse: Int = 1

    let logger: Logger
    var serverHostname: String = "localhost"
    var serverPort: Int = 666
    var channel: GRPCChannel?
    var group: MultiThreadedEventLoopGroup
    var server: Server_CreatureServerAsyncClient?
   
    let numberOfThreads: Int = 3
    
    // Joystick streaming stuff
    var stopSignalReceived: Bool = false
    
    // Animation playing stuff
    var isPlayingAnimation = false
    var emergencyStop = false
    
    
    init() {
        self.logger = Logger(subsystem: "io.opsnlops.CreatureController", category: "CreatureServerClient")
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: numberOfThreads)
        logger.debug("Created the EventLoopGroup with \(self.numberOfThreads) threads")
    }
    
    func connect(serverHostname: String, serverPort: Int) throws {
        self.serverHostname = serverHostname
        self.serverPort = serverPort
   
        DispatchQueue.main.async {
            self.appState!.currentActivity = .connectingToServer
        }
        
        logger.info("GRPCClient connect() with hostname: \(self.serverHostname), port: \(self.serverPort)")
   
    
        self.channel = try GRPCChannelPool.with(
            target: .host(self.serverHostname, port: self.serverPort),
            transportSecurity: .plaintext,
            eventLoopGroup: group
          )
        logger.debug("created the channel")
        
        if channel != nil {
            self.server = Server_CreatureServerAsyncClient(channel: channel!)
            logger.debug("created the client")
        }
        
        logger.debug("done with connect()")
        
        DispatchQueue.main.async {
            self.appState!.currentActivity = .idle
        }
    }
    
    func close() throws {
            try channel?.close().wait()
            try group.syncShutdownGracefully()
        }
    
    func getHostname() -> String {
        return self.serverHostname
    }
    
    
    
    func streamLogs(logViewModel: LogViewModel, logFilter: Server_LogFilter, stopFlag: StopFlag) async {
        
        logger.info("Making a request to get logs from the server")
        
        do {
            for try await logItem in self.server!.streamLogs(logFilter) {
                
            // If we gotta stop, it's time to stop 😅
            if stopFlag.shouldStop {
               break
           }

            await MainActor.run {
                logViewModel.addLogItem(logItem)
            }
          }
            
        } catch {
          print("RPC failed: \(error)")
        }
        
        logger.info("Stopping streaming logs from the server")
        
    }
    
    
}

    
/**
 Quick mock that doesn't do much, but it exists! :)
 */
class MockCreatureServerClient: CreatureServerClientProtocol {
    var appState: AppState?
    var audioManager: AudioManager?

    func connect(serverHostname: String, serverPort: Int) throws {
        // Possibly log the action or increment a counter to verify this method was called
    }

    func close() throws {
        // Mock implementation
    }

    func getHostname() -> String {
        // Return a dummy hostname
        return "localhost"
    }

    func streamLogs(logViewModel: LogViewModel, logFilter: Server_LogFilter, stopFlag: StopFlag) async {
        // Mock implementation
    }

    func streamJoystick(joystick: Joystick, creature: Creature, universe: UInt32) async throws {
        // Mock implementation, possibly throw an error if needed for testing error handling
    }

    func searchCreatures(creatureName: String) async throws -> Result<Creature, ServerError> {
        // Return a successful result with a mock creature, or throw an error for testing
        return .success(Creature.mock())
    }

    func getCreature(creatureId: Data) async throws -> Result<Creature, ServerError> {
        // Return a successful result with a mock creature, or throw an error for testing
        return .success(Creature.mock())
    }

    func getAllCreatures() async -> Result<[Creature], ServerError> {
        // Return a successful result with an array of mock creatures
        return .success([Creature.mock(), Creature.mock()])
    }

    func createAnimation(animation: Animation) async -> Result<String, ServerError> {
        // Return a success result with a mock response
        return .success("Animation created successfully")
    }

    func listAnimations(creature: Creature) async -> Result<[AnimationMetadata], ServerError> {
        // Return a successful result with an array of mock `AnimationMetadata`
        return .success([AnimationMetadata.mock(), AnimationMetadata.mock()])
    }

    func getAnimation(animationId: Data) async -> Result<Animation, ServerError> {
        // Return a successful result with a mock `Animation`
        return .success(Animation.mock())
    }

    func stopPlayingPlayist(universe: UInt32) async throws -> Result<String, ServerError> {
        // Return a success result with a mock response
        return .success("Playlist stopped")
    }

    func getPlaylist(playistId: Data) async throws -> Result<Playlist, ServerError> {
        // Return a successful result with a mock `Playlist`
        return .success(Playlist.mock())
    }

    func startPlayingPlaylist(universe: UInt32, playlistId: Data) async throws -> Result<String, ServerError> {
        // Return a success result with a mock response
        return .success("Playlist started")
    }

    // Assume `Creature`, `AnimationMetadata`, `Animation`, and `Playlist` have mock initializers or static mock methods
}

