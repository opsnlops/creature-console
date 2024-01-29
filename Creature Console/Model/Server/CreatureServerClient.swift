
import Foundation
import GRPC
import NIOCore
import NIOPosix
import OSLog
import SwiftUI
import SwiftProtobuf



class CreatureServerClient : ObservableObject {
    static let shared = CreatureServerClient()
    
    var appState : AppState?
    
    // Audio stuff
    var audioManager : AudioManager?
    @AppStorage("audioFilePath") var audioFilePath: String = ""
    
    @AppStorage("useOurJoystick") private var useOurJoystick: Bool = true
    
    let logger: Logger
    var serverHostname: String = "localhost"
    var serverPort: Int = 666
    var channel: GRPCChannel?
    var group: MultiThreadedEventLoopGroup
    var server: Server_CreatureServerAsyncClient?
   
    
    // Joystick streaming stuff
    var stopSignalReceived: Bool = false
    
    // Animation playing stuff
    var isPlayingAnimation = false
    var emergencyStop = false
    
    
    init() {
        self.logger = Logger(subsystem: "io.opsnlops.CreatureController", category: "CreatureServerClient")
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: 3)
        logger.debug("created the group")
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
    
    func searchCreatures(creatureName: String) async throws -> Server_Creature {
        
        logger.debug("attempting to fetch \(creatureName)")
        
        var name = Server_CreatureName()
        name.name = creatureName
        
        logger.debug("calling searchCreatures() now")
        let creature = try await server?.searchCreatures(name) ?? Server_Creature()
        
        return creature
    }
    
    
    func getCreature(creatureId: Data) async throws -> Server_Creature {
        
        logger.debug("attempting to fetch creature \(DataHelper.dataToHexString(data: creatureId))")
    
        var id = Server_CreatureId()
        id.id = creatureId
        
        let creature = try await server?.getCreature(id) ?? Server_Creature()
        
        return creature
    }
    
    /**
     Returns a listing of all of the Creatures that we know about
     */
    func listCreatures() async throws -> [CreatureIdentifier] {
        
        logger.info("attempting to list all creatures from the server")
        
        var creatures : [CreatureIdentifier]
        creatures = []
        
        // Default to sorting by name. TODO: Maybe change this later?
        var filter : Server_CreatureFilter
        filter = Server_CreatureFilter()
        filter.sortBy = Server_SortBy.name
        
        // Try, or return an empty response
        let list = try await server?.listCreatures(filter) ?? Server_ListCreaturesResponse()
        
        for id in list.creaturesIds {
            
            var ci : CreatureIdentifier
            ci = CreatureIdentifier(id: id.id, name: id.name)
            creatures.append(ci)
            logger.debug("found creature \(ci.name)")
        }
        
        logger.debug("total creatures found: \(creatures.count)")
        return creatures
        
    }
    
    func getAllCreatures() async throws -> [Server_Creature] {
        
        logger.info("attempting to get all of the creatures from the server")
        
        var creatures : [Server_Creature]
        creatures = []
        
        // Default to sorting by name.
        var filter : Server_CreatureFilter
        filter = Server_CreatureFilter()
        filter.sortBy = Server_SortBy.name
        
        // Try, or return an empty response
        let list = try await server?.getAllCreatures(filter) ?? Server_GetAllCreaturesResponse()
        
        for c in list.creatures {
            creatures.append(c)
            logger.debug("found creature \(c.name)")
        }
        
        logger.debug("total creatures found: \(creatures.count)")
        return creatures
        
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
    
    func createAnimation(animation: Animation) async -> Result<String, ServerError> {
        
        logger.info("Attempting to create a new Animation in the database")
        
        logger.debug("Animation Title: \(animation.metadata.title)")
        logger.debug("Number of frames: \(animation.numberOfFrames) and \(animation.frames.count)")
                
        do {
            let serverAnimation = try animation.toServerAnimation()
            let response = try await server?.createAnimation(serverAnimation)
            return .success("Server said: \(response?.message ?? "???")")
        }
        catch SwiftProtobuf.BinaryDecodingError.truncated {
            logger.error("Animation was unable to be decoded because it was truncated")
            return .failure(.communicationError("Unable to save animation due to the protobuf being truncated. 😅"))
        }
        catch SwiftProtobuf.BinaryDecodingError.malformedProtobuf {
            logger.error("Animation was unable to be decoded because the protobuf was malformed")
            return .failure(.dataFormatError("Unable to save animation due to the protobuf being malformed. 🤔"))
        }
        catch {
            logger.error("Unable to save an animation to the database: \(error)")
            return .failure(.databaseError("Server said: \(error.localizedDescription), (\(error))"))
        }
    }
    
    /**
     Update an animation in the database.
     
     This effectively called `replace_one()` on the MongoDB side, with the `_id` of the animation we're updating.
     */
    func updateAnimation(animationToUpdate: Animation) async -> Result<String, ServerError> {
        
        logger.info("Attempting to update an animation in the database")
 
        do {
            let serverAnimation = try animationToUpdate.toServerAnimation()
            let response = try await server?.updateAnimation(serverAnimation)
            return .success("\(response?.message ?? "😅")")
        }
        catch SwiftProtobuf.BinaryDecodingError.truncated {
            logger.error("Animation was unable to be decoded because it was truncated")
            return .failure(.dataFormatError("Unable to update an animation due to the protobuf being truncated. 😅"))
        }
        catch SwiftProtobuf.BinaryDecodingError.malformedProtobuf {
            logger.error("Animation was unable to be decoded because the protobuf was malformed")
            return .failure(.dataFormatError("Unable to update an animation due to the protobuf being malformed. 🤔"))
        }
        catch {
            logger.error("Unable to update an animation in the database: \(error)")
            return .failure(.databaseError("Server said: \(error.localizedDescription), (\(error))"))
        }
    }
    
    func listAnimations(creatureType: Server_CreatureType) async -> Result<[AnimationIdentifier], ServerError> {
        
        // TODO: Is the the right way to log this? (with .rawValue)
        logger.info("attempting to get all animations for creature type \(creatureType.rawValue)")
        
        var metadatas : [AnimationIdentifier]
        metadatas = []
        
        do {
            var filter = Server_AnimationFilter()
            filter.type = creatureType
            
            let response = try await server?.listAnimations(filter) ?? Server_ListAnimationsResponse()
            
            for a in response.animations {
                metadatas.append(AnimationIdentifier(serverAnimationIdentifier: a))
            }
            
            logger.info("got all animations for type \(creatureType.rawValue)")
            return .success(metadatas)
            
        }
        catch {
            logger.error("Unable to get animations for creature type \(creatureType.rawValue)")
            return .failure(.otherError("Server said: \(error.localizedDescription), (\(error))"))
        }
        
    }
    
    
    
    func getAnimation(animationId: Data) async -> Result<Animation, ServerError>  {
        
        logger.debug("attempting to fetch animation \(DataHelper.dataToHexString(data: animationId))")
    
        var id = Server_AnimationId()
        id.id = animationId
        
        do {
            
            if let serverAnimation = try await server?.getAnimation(id) {
                logger.info("loaded animation \(DataHelper.dataToHexString(data: animationId))")
                return .success(Animation(fromServerAnimation: serverAnimation))
            }
            
            return .failure(.notFound("Unable to locate animation \(DataHelper.dataToHexString(data: animationId))"))
            
        }
        catch {
            logger.error("Unable to get animation \(DataHelper.dataToHexString(data: animationId))")
            return .failure(.otherError("Server said: \(error.localizedDescription), (\(error))"))
        }
        
    }
}



extension CreatureServerClient {
    
    static func mock() -> CreatureServerClient {
        return MockCreatureServerClient()
    }
    
    private class MockCreatureServerClient: CreatureServerClient {
        
        override init() {
            super.init()
        }
        
        override func connect(serverHostname: String, serverPort: Int) throws {
            // Empty implementation for mock
        }
        
        override func close() throws {
            // Empty implementation for mock
        }
        
        override func searchCreatures(creatureName: String) async throws -> Server_Creature {
            return Server_Creature() // Return empty creature object
        }
        
        override func getCreature(creatureId: Data) async throws -> Server_Creature {
            return Server_Creature() // Return empty creature object
        }
        
        override func listCreatures() async throws -> [CreatureIdentifier] {
            return [] // Return empty list
        }
        
        override func getAllCreatures() async throws -> [Server_Creature] {
            return [] // Return empty list
        }
        
        override func streamLogs(logViewModel: LogViewModel, logFilter: Server_LogFilter, stopFlag: StopFlag) async {
            // Empty implementation for mock
        }
        
        override func createAnimation(animation: Animation) async -> Result<String, ServerError> {
            return .success("Animation created (mock)") // Return success message
        }
        
        override func listAnimations(creatureType: Server_CreatureType) async -> Result<[AnimationIdentifier], ServerError> {
            return .success([]) // Return empty list
        }
        
        override func getAnimation(animationId: Data) async -> Result<Animation, ServerError> {
            return .success(Animation.mock())
        }
    }
}
