import ArgumentParser
import Common
import Foundation

extension CreatureCLI {

  struct Creatures: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Mess with the Creatures",
      subcommands: [List.self, Search.self, Detail.self, Validate.self]
    )

    @OptionGroup()
    var globalOptions: GlobalOptions

    struct List: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "List the creatures on the server",
        discussion:
          "This command will print out a table of the creatures that the server knows about."
      )

      @OptionGroup()
      var globalOptions: GlobalOptions

      func run() async throws {

        let server = getServer(config: globalOptions)

        let result = await server.getAllCreatures()
        switch result {
        case .success(let creatures):

          print("\nKnown Creatures:\n")
          printTable(
            creatures,
            columns: [
              TableColumn(title: "Name", valueProvider: { $0.name }),
              TableColumn(title: "ID", valueProvider: { $0.id }),
              TableColumn(
                title: "Offset", valueProvider: { String($0.channelOffset) }),
              TableColumn(
                title: "Mouth Slot", valueProvider: { String($0.mouthSlot) }),
              TableColumn(
                title: "Audio", valueProvider: { String($0.audioChannel) }),
              TableColumn(
                title: "Inputs", valueProvider: { String($0.inputs.count) }),
            ])

          print(
            "\n\(creatures.count) creature(s) on server at \(server.serverHostname)\n")

        case .failure(let error):
          throw failWithMessage("Error fetching creatures: \(error.localizedDescription)")
        }
      }

    }

    struct Search: AsyncParsableCommand {
      @Argument(help: "The name of the creature to search for.")
      var name: String

      @OptionGroup()
      var globalOptions: GlobalOptions

      func run() async throws {
        // Use globalOptions here
        print(
          "Searching for creature \(name) on \(globalOptions.host):\(globalOptions.port) using TLS: \(!globalOptions.insecure)"
        )
      }
    }

    struct Detail: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Show details for a single creature by ID")

      @OptionGroup()
      var globalOptions: GlobalOptions

      @Argument(help: "Creature ID to show")
      var creatureId: CreatureIdentifier

      func run() async throws {
        let server = getServer(config: globalOptions)
        let result = try await server.getCreature(creatureId: creatureId)
        switch result {
        case .success(let creature):
          print(creatureDetails(creature))
        case .failure(let error):
          throw failWithMessage("Error fetching creature: \(error.localizedDescription)")
        }
      }
    }

    struct Validate: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Validate a creature configuration JSON file",
        discussion:
          "This command uploads a creature configuration file for validation without persisting it. It also verifies referenced animations exist and belong to the creature."
      )

      @Argument(help: "Path to the creature configuration JSON file to validate")
      var inputPath: String

      @OptionGroup()
      var globalOptions: GlobalOptions

      func run() async throws {
        let inputURL = URL(fileURLWithPath: inputPath).standardizedFileURL
        let fileManager = FileManager.default

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: inputURL.path, isDirectory: &isDirectory)
        else {
          throw failWithMessage("Input file \(inputURL.path) does not exist.")
        }
        guard !isDirectory.boolValue else {
          throw failWithMessage(
            "Input path \(inputURL.path) is a directory. Provide a JSON file.")
        }

        let rawConfig: String
        do {
          rawConfig = try String(contentsOf: inputURL, encoding: .utf8)
        } catch {
          throw failWithMessage("Unable to read JSON file: \(error.localizedDescription)")
        }

        guard !rawConfig.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
          throw failWithMessage("The provided JSON file is empty.")
        }

        let server = getServer(config: globalOptions)
        let result = await server.validateCreatureConfig(rawConfig: rawConfig)
        switch result {
        case .success(let payload):
          let creatureId = payload.creatureId ?? "unknown"
          if payload.valid {
            print("✅ Creature config is valid for creature \(creatureId)")
          } else {
            print("❌ Creature config is invalid for creature \(creatureId)")
          }

          if !payload.missingAnimationIds.isEmpty {
            print("Missing animations:")
            payload.missingAnimationIds.forEach { print("  - \($0)") }
          }

          if !payload.mismatchedAnimationIds.isEmpty {
            print("Animations with mismatched creatures:")
            for animationId in payload.mismatchedAnimationIds {
              let animationResult = await server.getAnimation(animationId: animationId)
              switch animationResult {
              case .success(let animation):
                let title = animation.metadata.title.isEmpty ? "Untitled" : animation.metadata.title
                let creatureIds = Set(animation.tracks.map { $0.creatureId })
                if creatureIds.count == 1, let creatureId = creatureIds.first {
                  let name = await fetchCreatureName(
                    server: server, creatureId: creatureId)
                  print("  - \(animationId) (\(title)) for creature \(name)")
                } else if creatureIds.isEmpty {
                  print("  - \(animationId) (\(title)) for creature unknown")
                } else {
                  let names = await fetchCreatureNames(
                    server: server, creatureIds: creatureIds)
                  print("  - \(animationId) (\(title)) for creatures \(names)")
                }
              case .failure:
                print("  - \(animationId) (unable to fetch animation details)")
              }
            }
          }

          if !payload.errorMessages.isEmpty {
            print("Other errors:")
            payload.errorMessages.forEach { print("  - \($0)") }
          }

        case .failure(let error):
          throw failWithMessage("Validation failed: \(error.localizedDescription)")
        }
      }

      private static func fetchCreatureName(
        server: CreatureServerClientProtocol, creatureId: CreatureIdentifier
      ) async -> String {
        do {
          let result = try await server.getCreature(creatureId: creatureId)
          switch result {
          case .success(let creature):
            return creature.name.isEmpty ? creatureId : creature.name
          case .failure:
            return creatureId
          }
        } catch {
          return creatureId
        }
      }

      private static func fetchCreatureNames(
        server: CreatureServerClientProtocol, creatureIds: Set<CreatureIdentifier>
      ) async -> String {
        let sorted = creatureIds.sorted()
        var names: [String] = []
        names.reserveCapacity(sorted.count)
        for creatureId in sorted {
          let name = await fetchCreatureName(server: server, creatureId: creatureId)
          names.append(name)
        }
        return names.joined(separator: ", ")
      }
    }
  }
}
