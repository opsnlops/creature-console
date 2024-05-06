

import ArgumentParser
import Foundation



extension CreatureCLI {

    struct Websocket: AsyncParsableCommand {
         static var configuration = CommandConfiguration(
             abstract: "WebSocket things",
             subcommands: [Connect.self]
         )

         @OptionGroup()
         var globalOptions: GlobalOptions

         struct Connect: AsyncParsableCommand {
             @OptionGroup()
             var globalOptions: GlobalOptions

             func run() async throws {

                 let server = getServer(config: globalOptions)
                 server.connectWebsocket()
                 print("connected to websocket")

                 for i in 0...19 {

                     do {
                         let result = await server.sendMessage("Hi \(i)")
                         switch(result) {

                         case .failure(let error):
                             print(" Error sending message: \(error.localizedDescription)")
                         default:
                             break
                         }
                     }

                     sleep(2)
                 }

                 server.disconnectWebsocket()
                 print("disconnected from websocket")

             }
         }
     }
}

