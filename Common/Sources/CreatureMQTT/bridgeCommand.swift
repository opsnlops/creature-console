import ArgumentParser
import Common
import Foundation
import Logging

extension CreatureMQTT {

    struct Bridge: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Bridge websocket events to MQTT topics",
            discussion:
                "Connects to the Creature websocket and republishes incoming messages to MQTT for Home Assistant consumption."
        )

        @Option(
            name: [.customShort("H"), .customLong("hide")],
            parsing: .upToNextOption,
            help: ArgumentHelp(
                "Hide specific message types (repeatable). Options: \(MQTTMessageProcessor.MessageType.helpText)",
                valueName: "type"
            )
        )
        var hide: [MQTTMessageProcessor.MessageType] = []

        @Option(
            name: [.customShort("O"), .customLong("only")],
            parsing: .upToNextOption,
            help: ArgumentHelp(
                "Publish only the specified message types (repeatable). Options: \(MQTTMessageProcessor.MessageType.helpText)",
                valueName: "type"
            )
        )
        var only: [MQTTMessageProcessor.MessageType] = []

        @Option(
            name: .long,
            help: "How many seconds to keep the bridge running (0 means run until cancelled)")
        var seconds: UInt32 = 0

        @Option(
            name: .long,
            help: "Log level (trace, debug, info, notice, warning, error, critical)")
        var logLevel: LogLevelOption = .info

        @Flag(
            name: [.customShort("d"), .long],
            help: "Enable debug logging (overrides --log-level)")
        var debug: Bool = false

        @OptionGroup()
        var globalOptions: GlobalOptions

        @OptionGroup()
        var mqttOptions: MQTTOptions

        func run() async throws {
            let loggerLevel = debug ? Logger.Level.debug : logLevel.level

            let mqttManager = MQTTClientManager(options: mqttOptions, logLevel: loggerLevel)

            let server = getServer(config: globalOptions)
            let resolver = CreatureNameResolver(
                initialNames: await preloadCreatureNames(from: server))
            let animationResolver = AnimationNameResolver(
                initialNames: await preloadAnimationNames(from: server))
            let fetcher: @Sendable (CreatureIdentifier) async -> String? = { id in
                let result = try? await server.getCreature(creatureId: id)
                switch result {
                case .success(let creature):
                    return creature.name
                case .failure, .none:
                    return nil
                }
            }
            let fetchAnimationName: @Sendable (AnimationIdentifier) async -> String? = { id in
                let result = await server.getAnimation(animationId: id)
                switch result {
                case .success(let animation):
                    return animation.metadata.title
                case .failure:
                    return nil
                }
            }
            let reloadAnimationNames: @Sendable () async -> [AnimationIdentifier: String] = {
                await preloadAnimationNames(from: server)
            }

            let hiddenTypes = Set(hide)
            let allowedTypes = only.isEmpty ? nil : Set(only)

            let processor = MQTTMessageProcessor(
                mqttClient: mqttManager,
                hiddenTypes: hiddenTypes,
                allowedTypes: allowedTypes,
                logLevel: loggerLevel,
                nameResolver: resolver,
                fetchCreatureName: fetcher,
                animationNameResolver: animationResolver,
                fetchAnimationName: fetchAnimationName,
                reloadAnimationNames: reloadAnimationNames,
                retainMessages: mqttOptions.retain
            )

            await server.connectWebsocket(processor: processor)
            print(
                "Connected to websocket at \(server.serverHostname), publishing to MQTT \(mqttOptions.mqttHost):\(mqttOptions.mqttPort)"
            )

            do {
                if seconds == 0 {
                    while !Task.isCancelled {
                        try await Task.sleep(for: .seconds(1))
                    }
                } else {
                    try await Task.sleep(for: .seconds(Int(seconds)))
                }
            } catch {
                // Allow cancellation to break the loop
            }

            _ = await server.disconnectWebsocket()
            await mqttManager.shutdown()
        }
    }
}

private func preloadCreatureNames(from server: CreatureServerClient) async -> [CreatureIdentifier:
    String]
{
    let result = await server.getAllCreatures()
    switch result {
    case .success(let creatures):
        return Dictionary(uniqueKeysWithValues: creatures.map { ($0.id, $0.name) })
    case .failure:
        return [:]
    }
}

private func preloadAnimationNames(from server: CreatureServerClient) async -> [AnimationIdentifier:
    String]
{
    let storedAnimations: [AnimationIdentifier: String]
    switch await server.listAnimations() {
    case .success(let animations):
        storedAnimations = Dictionary(uniqueKeysWithValues: animations.map { ($0.id, $0.title) })
    case .failure:
        storedAnimations = [:]
    }

    let adHocAnimations: [AnimationIdentifier: String]
    switch await server.listAdHocAnimations() {
    case .success(let adHoc):
        adHocAnimations = Dictionary(uniqueKeysWithValues: adHoc.map { ($0.id, $0.metadata.title) })
    case .failure:
        adHocAnimations = [:]
    }

    return storedAnimations.merging(adHocAnimations) { current, _ in current }
}

enum LogLevelOption: String, ExpressibleByArgument {
    case trace, debug, info, notice, warning, error, critical

    var level: Logger.Level {
        switch self {
        case .trace:
            return .trace
        case .debug:
            return .debug
        case .info:
            return .info
        case .notice:
            return .notice
        case .warning:
            return .warning
        case .error:
            return .error
        case .critical:
            return .critical
        }
    }
}
