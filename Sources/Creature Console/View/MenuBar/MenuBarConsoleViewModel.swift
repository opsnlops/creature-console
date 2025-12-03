import Common
import Foundation
import OSLog

@MainActor
final class MenuBarConsoleViewModel: ObservableObject {

    @Published private(set) var connectionState: WebSocketConnectionState = .disconnected
    @Published private(set) var preparedAnimations: [AdHocAnimationSummary] = []
    @Published private(set) var playlists: [Playlist] = []
    @Published private(set) var jobInfos: [JobStatusStore.JobInfo] = []
    @Published private(set) var latestMotorInPower: Double?
    @Published private(set) var latestMotorInVoltage: Double?
    @Published private(set) var lastUpdated: Date?
    @Published var inputText: String = ""
    @Published var errorMessage: String?

    private let server: CreatureServerClient
    private let jobStore: JobStatusStore
    private let healthCache: CreatureHealthCache
    private let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "MenuBar")
    private var observers: [Task<Void, Never>] = []
    private var hasStarted = false
    private var selectedCreatureId: CreatureIdentifier = ""

    init(
        server: CreatureServerClient = .shared,
        jobStore: JobStatusStore = .shared,
        healthCache: CreatureHealthCache = .shared
    ) {
        self.server = server
        self.jobStore = jobStore
        self.healthCache = healthCache
    }

    deinit {
        observers.forEach { $0.cancel() }
    }

    func start(selectedCreatureId: CreatureIdentifier) {
        guard !hasStarted else {
            updateSelectedCreature(selectedCreatureId)
            return
        }
        hasStarted = true
        self.selectedCreatureId = selectedCreatureId

        observers.append(
            Task { [weak self] in
                guard let self else { return }
                let stream = await WebSocketStateManager.shared.stateUpdates
                for await state in stream {
                    await MainActor.run {
                        self.connectionState = state
                    }
                }
            }
        )

        observers.append(
            Task { [weak self] in
                guard let self else { return }
                let stream = await jobStore.events()
                for await event in stream {
                    await MainActor.run {
                        self.handle(jobEvent: event)
                    }
                }
            }
        )

        observers.append(
            Task { [weak self] in
                guard let self else { return }
                let stream = await healthCache.stateUpdates
                for await state in stream {
                    await MainActor.run {
                        self.updateHealthSnapshot(
                            cacheState: state,
                            creatureId: self.selectedCreatureId
                        )
                    }
                }
            }
        )

        Task { [weak self] in
            guard let self else { return }
            await self.bootstrapHealth(for: selectedCreatureId)
        }

        Task { [weak self] in
            guard let self else { return }
            await self.refreshPreparedAnimations()
        }

        Task { [weak self] in
            guard let self else { return }
            await self.refreshPlaylists()
        }
    }

    func updateSelectedCreature(_ creatureId: CreatureIdentifier) {
        selectedCreatureId = creatureId
        Task { [weak self] in
            guard let self else { return }
            await self.bootstrapHealth(for: creatureId)
        }
    }

    func refreshPreparedAnimations() async {
        let result = await server.listAdHocAnimations()
        switch result {
        case .success(let animations):
            preparedAnimations = animations.sorted {
                ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast)
            }
            errorMessage = nil
        case .failure(let error):
            errorMessage = ServerError.detailedMessage(from: error)
            logger.error("Failed to load ad-hoc animations: \(error.localizedDescription)")
        }
    }

    func refreshPlaylists() async {
        let result = await server.getAllPlaylists()
        switch result {
        case .success(let list):
            playlists = list.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            errorMessage = nil
        case .failure(let error):
            errorMessage = ServerError.detailedMessage(from: error)
            logger.error("Failed to load playlists: \(error.localizedDescription)")
        }
    }

    func playInstant(resumePlaylist: Bool) async {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Enter something for the creature to say."
            return
        }
        guard !selectedCreatureId.isEmpty else {
            errorMessage = "Choose a creature before sending speech."
            return
        }

        let response = await server.createAdHocSpeechAnimation(
            creatureId: selectedCreatureId,
            text: trimmed,
            resumePlaylist: resumePlaylist
        )

        switch response {
        case .success:
            inputText = ""
            errorMessage = nil
            await refreshPreparedAnimations()
        case .failure(let error):
            errorMessage = ServerError.detailedMessage(from: error)
        }
    }

    func cueAdHoc(resumePlaylist: Bool) async {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Enter something for the creature to say."
            return
        }
        guard !selectedCreatureId.isEmpty else {
            errorMessage = "Choose a creature before queuing speech."
            return
        }

        let response = await server.prepareAdHocSpeechAnimation(
            creatureId: selectedCreatureId,
            text: trimmed,
            resumePlaylist: resumePlaylist
        )

        switch response {
        case .success:
            inputText = ""
            errorMessage = nil
            await refreshPreparedAnimations()
        case .failure(let error):
            errorMessage = ServerError.detailedMessage(from: error)
        }
    }

    func triggerPrepared(
        animationId: AnimationIdentifier,
        resumePlaylist: Bool
    ) async {
        let response = await server.triggerPreparedAdHocSpeech(
            animationId: animationId,
            resumePlaylist: resumePlaylist
        )
        switch response {
        case .success:
            errorMessage = nil
        case .failure(let error):
            errorMessage = ServerError.detailedMessage(from: error)
        }
    }

    func startPlaylist(
        _ playlist: Playlist,
        universe: UniverseIdentifier
    ) async {
        let response = await server.startPlayingPlaylist(
            universe: universe,
            playlistId: playlist.id
        )
        if case .failure(let error) = response {
            errorMessage = ServerError.detailedMessage(from: error)
        } else {
            errorMessage = nil
        }
    }

    func stopPlaylist(universe: UniverseIdentifier) async {
        let response = await server.stopPlayingPlaylist(universe: universe)
        if case .failure(let error) = response {
            errorMessage = ServerError.detailedMessage(from: error)
        } else {
            errorMessage = nil
        }
    }

    func reconnect() {
        Task {
            await server.connectWebsocket(processor: SwiftMessageProcessor.shared)
        }
    }

    private func handle(jobEvent: JobStatusStore.Event) {
        switch jobEvent {
        case .updated(let info):
            guard info.jobType == .adHocSpeech || info.jobType == .adHocSpeechPrepare else {
                return
            }
            upsert(job: info)
        case .removed(let id):
            jobInfos.removeAll { $0.jobId == id }
        }
    }

    private func upsert(job: JobStatusStore.JobInfo) {
        if job.status.isTerminal {
            if job.status == .completed,
                job.jobType == .adHocSpeechPrepare || job.jobType == .adHocSpeech
            {
                Task { [weak self] in await self?.refreshPreparedAnimations() }
            }
            jobInfos.removeAll { $0.jobId == job.jobId }
            return
        }

        if let index = jobInfos.firstIndex(where: { $0.jobId == job.jobId }) {
            jobInfos[index] = job
        } else {
            jobInfos.append(job)
        }
        jobInfos.sort { $0.lastUpdated > $1.lastUpdated }
    }

    private func bootstrapHealth(for creatureId: CreatureIdentifier) async {
        guard !creatureId.isEmpty else {
            latestMotorInPower = nil
            latestMotorInVoltage = nil
            lastUpdated = nil
            return
        }

        let result = await healthCache.latestBoardSensorData(forCreature: creatureId)
        switch result {
        case .success(let report):
            updateHealth(using: report)
        case .failure:
            latestMotorInPower = nil
            latestMotorInVoltage = nil
            lastUpdated = nil
        }
    }

    private func updateHealthSnapshot(
        cacheState: CreatureHealthCacheState,
        creatureId: CreatureIdentifier
    ) {
        guard !creatureId.isEmpty else {
            latestMotorInPower = nil
            latestMotorInVoltage = nil
            lastUpdated = nil
            return
        }
        if let report = cacheState.boardSensorCache[creatureId]?.last {
            updateHealth(using: report)
        }
    }

    private func updateHealth(using report: BoardSensorReport) {
        let motorPower = report.powerReports.first { sensor in
            let name = sensor.name.lowercased()
            return name.contains("motor") && name.contains("in")
        }
        lastUpdated = report.timestamp
        latestMotorInPower = motorPower?.power
        latestMotorInVoltage = motorPower?.voltage
    }
}
