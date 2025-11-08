import Combine
import Common
import Foundation
import OSLog
import PlaylistRuntime

@MainActor
final class LightweightClientViewModel: ObservableObject {

    @Published private(set) var connectionState: WebSocketConnectionState = .disconnected
    @Published private(set) var preparedAnimations: [AdHocAnimationSummary] = []
    @Published private(set) var playlists: [Playlist] = []
    @Published private(set) var jobInfos: [LightweightJobStore.JobInfo] = []
    @Published private(set) var creatures: [Creature] = []
    @Published private(set) var latestMotorInPower: Double?
    @Published private(set) var latestMotorInVoltage: Double?
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var defaultCreatureId: CreatureIdentifier = ""
    @Published var inputText: String = ""
    @Published var resumePlaylistAfterPlayback: Bool = true
    @Published var errorMessage: String?

    private let controller: LightweightClientController
    private let playlistRuntime: PlaylistRuntimeStore
    private var observers: [Task<Void, Never>] = []
    private var cancellables: Set<AnyCancellable> = []
    private let logger = Logger(subsystem: "io.opsnlops.LightweightClient", category: "ViewModel")

    init(
        controller: LightweightClientController,
        playlistRuntime: PlaylistRuntimeStore = .shared
    ) {
        self.controller = controller
        self.playlistRuntime = playlistRuntime
        startObservers()
        Task {
            await controller.bootstrap()
        }
        Task {
            await refreshSettingsSnapshot()
            await refreshPreparedAnimations()
            await refreshPlaylists()
        }
        bindPlaylistRuntime()
    }

    deinit {
        observers.forEach { $0.cancel() }
    }

    func refreshPreparedAnimations() async {
        let result = await controller.refreshAdHocAnimations()
        await handle(result, assignTo: \.preparedAnimations)
    }

    func refreshPlaylists() async {
        let result = await controller.fetchPlaylists()
        await handle(result, assignTo: \.playlists)
    }

    func playInstant() async {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Enter something for the creature to say."
            return
        }

        let response = await controller.triggerInstantAdHoc(
            text: trimmed,
            resumePlaylist: resumePlaylistAfterPlayback
        )

        switch response {
        case .success:
            inputText = ""
            errorMessage = nil
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    func cueAdHoc() async {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Enter something for the creature to say."
            return
        }

        let response = await controller.cueAdHoc(
            text: trimmed,
            resumePlaylist: resumePlaylistAfterPlayback
        )

        switch response {
        case .success:
            inputText = ""
            errorMessage = nil
            await refreshPreparedAnimations()
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    func triggerPrepared(animationId: AnimationIdentifier) async {
        let response = await controller.triggerPreparedAdHoc(
            animationId: animationId,
            resumePlaylist: resumePlaylistAfterPlayback
        )
        switch response {
        case .success:
            errorMessage = nil
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    func startPlaylist(_ playlist: Playlist) async {
        let response = await controller.startPlaylist(playlist.id)
        if case .failure(let error) = response {
            errorMessage = error.localizedDescription
        } else {
            errorMessage = nil
        }
    }

    func stopPlaylist() async {
        let response = await controller.stopPlaylist()
        if case .failure(let error) = response {
            errorMessage = error.localizedDescription
        } else {
            errorMessage = nil
        }
    }

    func reconnect() {
        Task {
            await controller.reconnectWebsocket()
        }
    }

    func refreshSettingsSnapshot() async {
        let settings = await controller.currentSettings()
        defaultCreatureId = settings.defaultCreatureId
        if settings.apiKey.isEmpty {
            errorMessage = nil
        }
    }

    func updateResumePlaylist(_ value: Bool) {
        playlistRuntime.resumePlaylistAfterPlayback = value
    }

    private func startObservers() {
        observers.append(
            Task { [weak self] in
                guard let self else { return }
                let stream = await WebSocketStateManager.shared.stateUpdates
                for await state in stream {
                    await MainActor.run {
                        self.connectionState = state
                        if state == .connected {
                            Task { [weak self] in
                                await self?.refreshCreatures()
                            }
                        }
                    }
                }
            }
        )

        observers.append(
            Task { [weak self] in
                guard let self else { return }
                let store = LightweightHealthStore.shared
                let stream = await store.updates()
                let initialCreature = await MainActor.run { self.defaultCreatureId }
                if let initial = await store.latestReport(for: initialCreature) {
                    await updateHealth(using: initial)
                }

                for await snapshot in stream {
                    let targetCreature = await MainActor.run { self.defaultCreatureId }
                    let trimmed = targetCreature.trimmingCharacters(in: .whitespacesAndNewlines)
                    let report = snapshot.report

                    if !trimmed.isEmpty && report.creatureId != trimmed {
                        continue
                    }

                    await updateHealth(using: report)
                }
            }
        )

        observers.append(
            Task { [weak self] in
                guard let self else { return }
                let stream = await LightweightJobStore.shared.events()
                for await event in stream {
                    await MainActor.run {
                        switch event {
                        case .updated(let info):
                            self.upsertJobInfo(info)
                        case .removed(let id):
                            self.jobInfos.removeAll { $0.jobId == id }
                        }
                    }
                }
            }
        )
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

    private func upsertJobInfo(_ info: LightweightJobStore.JobInfo) {
        guard info.jobType == .adHocSpeech || info.jobType == .adHocSpeechPrepare else { return }
        if let index = jobInfos.firstIndex(where: { $0.jobId == info.jobId }) {
            jobInfos[index] = info
        } else {
            jobInfos.append(info)
        }
        jobInfos.sort { lhs, rhs in
            lhs.lastUpdated > rhs.lastUpdated
        }

        if info.jobType == .adHocSpeechPrepare, info.status == .completed {
            Task {
                await refreshPreparedAnimations()
            }
        }
    }

    private func bindPlaylistRuntime() {
        resumePlaylistAfterPlayback = playlistRuntime.resumePlaylistAfterPlayback
        playlistRuntime.$resumePlaylistAfterPlayback
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                self?.resumePlaylistAfterPlayback = value
            }
            .store(in: &cancellables)
    }

    private func handle<Value>(
        _ result: Result<Value, ServerError>,
        assignTo keyPath: ReferenceWritableKeyPath<LightweightClientViewModel, Value>
    ) async {
        switch result {
        case .success(let value):
            self[keyPath: keyPath] = value
            errorMessage = nil
        case .failure(let error):
            logger.error("Server error: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    func refreshCreatures() async {
        let result = await controller.fetchCreatures()
        switch result {
        case .success(let list):
            let sorted = list.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            creatures = sorted
            guard !sorted.isEmpty else { return }
            if defaultCreatureId.isEmpty,
                let first = sorted.first
            {
                defaultCreatureId = first.id
                await controller.updateDefaultCreature(first.id)
            } else if !sorted.contains(where: { $0.id == defaultCreatureId }),
                let first = sorted.first
            {
                defaultCreatureId = first.id
                await controller.updateDefaultCreature(first.id)
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }
}
