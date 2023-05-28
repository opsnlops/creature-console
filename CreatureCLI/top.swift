
import ArgumentParser
import GRPC
import NIOCore
import NIOPosix

@main
struct CreatureCLI: AsyncParsableCommand {
    
    @Option(help: "The port to connect to")
    var port: Int = 6666

    @Option(help: "The server name to connect to")
    var host: String = "10.3.2.11"
    
    @Argument(help: "The creature to search for!")
    var name: String = ""

    mutating func run() async throws {

        print("hello \(name)")
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)

        // Make sure the group is shutdown when we're done with it.
        defer {
          try! group.syncShutdownGracefully()
        }

        // Configure the channel, we're not using TLS so the connection is `insecure`.
        let channel = try GRPCChannelPool.with(
            target: .host(self.host, port: self.port),
          transportSecurity: .plaintext,
          eventLoopGroup: group
        )

        // Close the connection when we're done with it.
        defer {
          try! channel.close().wait()
        }

        // Provide the connection to the generated client.
        let server = Server_CreatureServerAsyncClient(channel: channel)

        // Form the request with the name, if one was provided.
          let request = Server_CreatureName.with {
              print("\($0)")
          $0.name = self.name
        }

        do {
            let creature = try await server.searchCreatures(request)
            print("Client received: \(creature.name)")
            print("Last upddated: \(creature.lastUpdated)")
        } catch {
          print("Client failed: \(error)")
        }
    }
}
