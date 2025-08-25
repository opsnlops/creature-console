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

    // AsyncStream for UI updates
    private let (stateStream, stateContinuation) = AsyncStream.makeStream(
        of: AnimationMetadataCacheState.self)

    var stateUpdates: AsyncStream<AnimationMetadataCacheState> {
        stateStream
    }

    private init() {}

    func addAnimationMetadata(_ metadata: AnimationMetadata, for id: AnimationIdentifier) {
        metadatas[id] = metadata
        empty = metadatas.isEmpty
        publishState()
    }

    private func publishState() {
        let currentState = AnimationMetadataCacheState(
            metadatas: metadatas,
            empty: empty
        )
        stateContinuation.yield(currentState)
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
