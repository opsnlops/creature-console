//
//  GRPCClient.swift
//  Creature Console
//
//  Created by April White on 4/4/23.
//

import Foundation
import GRPC
import NIOCore
import NIOPosix
import Logging
import SwiftUI


class CreatureServerClient : ObservableObject {
    static let shared = CreatureServerClient()
    
    let logger: Logger
    var serverHostname: String = "localhost"
    var serverPort: Int = 666
    var channel: GRPCChannel?
    var group: MultiThreadedEventLoopGroup
    var server: Server_CreatureServerAsyncClient?
   
    
    // Joystick streaming stuff
    var stopSignalReceived: Bool = false
    
    
    init() {
        self.logger = Logger(label: "GRPCClient")
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: 3)
        logger.debug("created the group")
    }
    
    func connect(serverHostname: String, serverPort: Int) throws {
        self.serverHostname = serverHostname
        self.serverPort = serverPort
   
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
        
        logger.debug("done with init()")
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
}
