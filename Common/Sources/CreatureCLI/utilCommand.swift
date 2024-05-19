import ArgumentParser
import Common
import Foundation

extension CreatureCLI {

    struct Util: AsyncParsableCommand {
        static var configuration = CommandConfiguration(
            abstract: "Helper utils that might be fun!",
            subcommands: [Oid.self]
        )

        @OptionGroup()
        var globalOptions: GlobalOptions


        struct Oid: AsyncParsableCommand {
            static var configuration = CommandConfiguration(
                abstract: "Generate a fresh OID",
                discussion:
                    "This command does nothing more than generate an oid that can be used for other things"
            )

            @OptionGroup()
            var globalOptions: GlobalOptions

            func run() async throws {

                print("\nHere's your shiny new OID: \(DataHelper.generateRandomId())\n")

            }
        }

    }
}

