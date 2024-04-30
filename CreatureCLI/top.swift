
import ArgumentParser


@main
struct CreatureCLI: AsyncParsableCommand {
    
    @Option(help: "The port to connect to")
    var port: Int = 8000

    @Option(help: "The server name to connect to")
    var host: String = "localhost"

    @Option(help: "Use TLS")
    var useTLS: Bool = false

    @Argument(help: "The creature to search for!")
    var name: String = ""

    mutating func run() async throws {

        let server = CreatureServerRestful()
        server.serverPort = port
        server.serverHostname = host
        server.useTLS = useTLS

        print("Server URL: \(server.makeBaseURL())")
        

        let result = await server.getAllCreatures()
            switch result {
            case .success(let creatures):
                print("Fetched creatures successfully:")
                for creature in creatures {
                    print("\(creature.name) - \(creature.notes)")
                }
            case .failure(let error):
                print("Error fetching creatures: \(error)")
        }
    }

}


