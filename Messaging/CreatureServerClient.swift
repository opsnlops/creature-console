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


class CreatureServerClient : ObservableObject {
    static let shared = CreatureServerClient()
    
    let logger: Logger
    var serverHostname: String = "localhost"
    var serverPort: Int = 666
    var channel: GRPCChannel?
    var group: MultiThreadedEventLoopGroup
    var server: Server_CreatureServerAsyncClient?
    
    
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
    
    func getCreature(creatureName: String) async throws -> Server_Creature {
        
        logger.debug("attempting to fetch \(creatureName)")
        
        var name = Server_CreatureName()
        name.name = creatureName
        
        logger.debug("calling getCreature() now")
        let creature = try await server?.getCreature(name) ?? Server_Creature()
        
        return creature
    }
    
    
}
