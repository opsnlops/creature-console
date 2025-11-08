import Combine
import Common
import Foundation
import Logging

public struct PlaylistRuntimeSnapshot: Identifiable, Equatable, Codable, Sendable {
    public let universe: UniverseIdentifier
    public let playlist: PlaylistIdentifier
    public let playing: Bool
    public let currentAnimation: AnimationIdentifier

    public var id: UniverseIdentifier { universe }

    public init(
        universe: UniverseIdentifier,
        playlist: PlaylistIdentifier,
        playing: Bool,
        currentAnimation: AnimationIdentifier
    ) {
        self.universe = universe
        self.playlist = playlist
        self.playing = playing
        self.currentAnimation = currentAnimation
    }

    public init(status: PlaylistStatus) {
        self.init(
            universe: status.universe,
            playlist: status.playlist,
            playing: status.playing,
            currentAnimation: status.currentAnimation
        )
    }
}

@MainActor
public final class PlaylistRuntimeStore: ObservableObject {
    public static let shared = PlaylistRuntimeStore()

    @Published public private(set) var playlistSnapshots:
        [UniverseIdentifier: PlaylistRuntimeSnapshot]
    @Published private(set) var orderedSnapshotsStorage: [PlaylistRuntimeSnapshot]
    @Published public private(set) var lastUpdated: Date?
    @Published public var resumePlaylistAfterPlayback: Bool {
        didSet {
            userDefaults.set(resumePlaylistAfterPlayback, forKey: Self.resumePreferenceKey)
        }
    }

    private let userDefaults: UserDefaults
    private let logger: Logging.Logger
    private let statusSubject = PassthroughSubject<PlaylistRuntimeSnapshot, Never>()

    private static let resumePreferenceKey = "PlaylistRuntime.resumePlaylistAfterPlayback"

    public init(
        userDefaults: UserDefaults = .standard,
        logger: Logging.Logger = Logging.Logger(label: "io.opsnlops.playlistruntime")
    ) {
        self.userDefaults = userDefaults
        self.playlistSnapshots = [:]
        self.orderedSnapshotsStorage = []
        self.resumePlaylistAfterPlayback =
            userDefaults.object(forKey: Self.resumePreferenceKey) as? Bool ?? true
        self.lastUpdated = nil
        var log = logger
        log.logLevel = .info
        self.logger = log
    }

    public func update(with status: PlaylistStatus) {
        update(with: PlaylistRuntimeSnapshot(status: status))
    }

    public func update(with snapshot: PlaylistRuntimeSnapshot) {
        playlistSnapshots[snapshot.universe] = snapshot
        orderedSnapshotsStorage = playlistSnapshots.values.sorted { $0.universe < $1.universe }
        lastUpdated = Date()
        statusSubject.send(snapshot)
        logger.debug("Updated playlist status for universe \(snapshot.universe)")
    }

    public func removeStatus(for universe: UniverseIdentifier) {
        playlistSnapshots.removeValue(forKey: universe)
        orderedSnapshotsStorage = playlistSnapshots.values.sorted { $0.universe < $1.universe }
        lastUpdated = Date()
        logger.debug("Removed playlist status for universe \(universe)")
    }

    public func clearAllStatuses() {
        playlistSnapshots.removeAll()
        orderedSnapshotsStorage = []
        lastUpdated = Date()
        logger.debug("Cleared all playlist statuses")
    }

    public func snapshot(for universe: UniverseIdentifier) -> PlaylistRuntimeSnapshot? {
        playlistSnapshots[universe]
    }

    public var orderedSnapshots: [PlaylistRuntimeSnapshot] {
        orderedSnapshotsStorage
    }

    public var statusUpdates: AnyPublisher<PlaylistRuntimeSnapshot, Never> {
        statusSubject.eraseToAnyPublisher()
    }
}
