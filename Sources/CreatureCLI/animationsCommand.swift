

import ArgumentParser


extension CreatureCLI {
    
    struct Animations: AsyncParsableCommand {
         static var configuration = CommandConfiguration(
             abstract: "View and work with animations",
             subcommands: [List.self]
         )

         @OptionGroup()
         var globalOptions: GlobalOptions

         struct List: AsyncParsableCommand {
             @OptionGroup()
             var globalOptions: GlobalOptions

             func run() async throws {
                 // Use globalOptions here
                 print("Fetching animations on \(globalOptions.host):\(globalOptions.port) using TLS: \(globalOptions.useTLS)")
             }
         }
     }
}
