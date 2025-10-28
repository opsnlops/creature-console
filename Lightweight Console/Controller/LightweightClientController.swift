import Common
import Logging
import LoggingOSLog
import OSLog

actor LightweightClientController {
    private let client: CreatureServerClient
    private let messageProcessor: LightweightMessageProcessor
    private let settingsStore: LightweightSettingsStore
    private let logger: Logging.Logger

    init(
        client: CreatureServerClient = .shared,
        messageProcessor: LightweightMessageProcessor = .shared,
        settingsStore: LightweightSettingsStore = .shared
    ) {
        self.client = client
        self.messageProcessor = messageProcessor
        self.settingsStore = settingsStore
        LoggingSystem.bootstrap(LoggingOSLog.init)
        var logger = Logging.Logger(label: "io.opsnlops.LightweightClient.Controller")
        logger.logLevel = .info
        self.logger = logger
    }

    func bootstrap() async {
        await applyConfiguration()
        await client.connectWebsocket(processor: messageProcessor)
    }

    func applyConfiguration() async {
        let settings = await settingsStore.currentSettings()
        let apiKey = await settingsStore.authToken()
        let backendHost =
            settings.backendHostname?.isEmpty == false
            ? settings.backendHostname!
            : settings.hostname

        do {
            try client.connect(
                serverHostname: backendHost,
                serverPort: settings.port,
                useTLS: settings.useTLS,
                serverProxyHost: apiKey.isEmpty ? nil : settings.hostname,
                apiKey: apiKey.isEmpty ? nil : apiKey
            )
            logger.info(
                "Configured server host \(backendHost):\(settings.port) (TLS: \(settings.useTLS)) proxy=\(apiKey.isEmpty ? "off" : "on")"
            )
        } catch {
            logger.error("Failed to configure server client: \(String(describing: error))")
        }
    }

    func reconnectWebsocket() async {
        await client.connectWebsocket(processor: messageProcessor)
    }

    func disconnectWebsocket() async {
        _ = await client.disconnectWebsocket()
    }

    func refreshAdHocAnimations() async -> Result<[AdHocAnimationSummary], ServerError> {
        await client.listAdHocAnimations()
    }

    func triggerInstantAdHoc(text: String, resumePlaylist: Bool) async -> Result<
        JobCreatedResponse, ServerError
    > {
        let settings = await settingsStore.currentSettings()
        let creatureId = settings.defaultCreatureId
        return await client.createAdHocSpeechAnimation(
            creatureId: creatureId, text: text, resumePlaylist: resumePlaylist)
    }

    func cueAdHoc(text: String, resumePlaylist: Bool) async -> Result<
        JobCreatedResponse, ServerError
    > {
        let settings = await settingsStore.currentSettings()
        let creatureId = settings.defaultCreatureId
        return await client.prepareAdHocSpeechAnimation(
            creatureId: creatureId, text: text, resumePlaylist: resumePlaylist)
    }

    func triggerPreparedAdHoc(animationId: AnimationIdentifier, resumePlaylist: Bool) async
        -> Result<
            String, ServerError
        >
    {
        await client.triggerPreparedAdHocSpeech(
            animationId: animationId, resumePlaylist: resumePlaylist)
    }

    func fetchPlaylists() async -> Result<[Playlist], ServerError> {
        await client.getAllPlaylists()
    }

    func fetchCreatures() async -> Result<[Creature], ServerError> {
        await client.getAllCreatures()
    }

    func startPlaylist(_ playlistId: PlaylistIdentifier) async -> Result<String, ServerError> {
        let universe = await settingsStore.activeUniverse()
        return await client.startPlayingPlaylist(universe: universe, playlistId: playlistId)
    }

    func stopPlaylist() async -> Result<String, ServerError> {
        let universe = await settingsStore.activeUniverse()
        return await client.stopPlayingPlaylist(universe: universe)
    }

    func updateSettings(_ settings: LightweightClientSettings, authToken: String) async {
        await settingsStore.update(settings: settings)
        await settingsStore.setAuthToken(authToken)
        await applyConfiguration()
        await reconnectWebsocket()
    }

    func updateUniverse(_ universe: UniverseIdentifier) async {
        await settingsStore.setActiveUniverse(universe)
    }

    func updateDefaultCreature(_ creatureId: CreatureIdentifier) async {
        var settings = await settingsStore.currentSettings()
        guard settings.defaultCreatureId != creatureId else { return }
        settings.defaultCreatureId = creatureId
        await settingsStore.update(settings: settings)
    }

    func currentSettings() async -> LightweightClientSettings {
        await settingsStore.currentSettings()
    }

    func currentAuthToken() async -> String {
        await settingsStore.authToken()
    }

    func activeUniverse() async -> UniverseIdentifier {
        await settingsStore.activeUniverse()
    }
}
