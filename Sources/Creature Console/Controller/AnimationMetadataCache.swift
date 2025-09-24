import Combine
import Common
import Foundation
import OSLog

struct AnimationMetadataCacheState: Sendable {
    let metadatas: [AnimationIdentifier: AnimationMetadata]
    let empty: Bool
}

actor AnimationMetadataCache {
    static let shared = AnimationMetadataCache()

    private var metadatas: [AnimationIdentifier: AnimationMetadata] = [:]
    private var empty: Bool = true

    private let logger = Logger(
        subsystem: "io.opsnlops.CreatureConsole", category: "AnimationMetadataCache")

    private var continuations: [UUID: AsyncStream<AnimationMetadataCacheState>.Continuation] = [:]

    var stateUpdates: AsyncStream<AnimationMetadataCacheState> {
        AsyncStream { continuation in
            let id = UUID()
            Task { [weak self] in
                await self?.addContinuation(id: id, continuation)
            }
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeContinuation(id) }
            }
        }
    }

    private func currentSnapshot() -> AnimationMetadataCacheState {
        AnimationMetadataCacheState(
            metadatas: metadatas,
            empty: empty
        )
    }

    private func addContinuation(id: UUID, _ continuation: AsyncStream<AnimationMetadataCacheState>.Continuation) {
        continuations[id] = continuation
        // Seed with the current state immediately
        continuation.yield(currentSnapshot())
    }

    private func removeContinuation(_ id: UUID) {
        continuations[id] = nil
    }

    private init() {}

    func addAnimationMetadata(_ metadata: AnimationMetadata, for id: AnimationIdentifier) {
        metadatas[id] = metadata
        empty = metadatas.isEmpty
        publishState()
    }

    private func publishState() {
        let snapshot = currentSnapshot()
        logger.debug("AnimationMetadataCache: Broadcasting state (count: \(self.metadatas.count), empty: \(self.empty))")
        for continuation in continuations.values {
            continuation.yield(snapshot)
        }
    }

    func removeAnimationMetadata(for id: AnimationIdentifier) {
        metadatas.removeValue(forKey: id)
        empty = metadatas.isEmpty
        publishState()
    }

    public func reload(with metadatas: [AnimationMetadata]) {
        let reloadedMetadatas = Dictionary(uniqueKeysWithValues: metadatas.map { ($0.id, $0) })
        self.metadatas = reloadedMetadatas
        self.empty = reloadedMetadatas.isEmpty
        publishState()
    }

    public func getById(id: AnimationIdentifier) -> Result<AnimationMetadata, ServerError> {
        if let metadata = metadatas[id] {
            return .success(metadata)
        } else {
            logger.warning("getById() called on an ID that wasn't in the cache! \(id)")
            return .failure(.notFound("Animation ID \(id) not found in the cache"))
        }
    }

    public func fetchMetadataListFromServer() async -> Result<String, ServerError> {
        let server = CreatureServerClient.shared

        logger.info("attempting to fetch the animation metadata list from the server")
        let fetchResult = await server.listAnimations()
        switch fetchResult {
        case .success(let metadataList):
            logger.debug("pulled \(metadataList.count) metadata from the server")
            self.reload(with: metadataList)
            return .success("Successfully loaded \(metadataList.count) animation metadata")
        case .failure(let error):
            logger.warning("Unable to fetch the list of animation metadata: \(error)")
            await AppState.shared.setSystemAlert(
                show: true, message: error.localizedDescription)
            return .failure(error)
        }
    }

    public func getCurrentState() -> AnimationMetadataCacheState {
        return AnimationMetadataCacheState(metadatas: metadatas, empty: empty)
    }
}
