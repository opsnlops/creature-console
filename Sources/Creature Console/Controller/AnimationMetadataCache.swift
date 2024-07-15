import Combine
import Common
import Foundation
import OSLog

/**
 A cache of the metadatas for all of the animations on the server. We do not keep the actual animations (those are huge), but it's good for us to have a local cache of the metadata.
 */
class AnimationMetadataCache: ObservableObject {
    static let shared = AnimationMetadataCache()

    @Published public private(set) var metadatas: [AnimationIdentifier: AnimationMetadata] = [:]
    @Published public private(set) var empty: Bool = true

    private let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "AnimationMetadataCache")
    private let queue = DispatchQueue(label: "com.creaturecache.queue", attributes: .concurrent)

    // Make sure we don't accidentally create two of these
    private init() {}


    func addAnimationMetadata(_ metadata: AnimationMetadata, for id: AnimationIdentifier) {
        queue.async(flags: .barrier) {
            var updatedMetas = self.metadatas
            updatedMetas[id] = metadata
            DispatchQueue.main.async {
                self.metadatas = updatedMetas
                self.empty = updatedMetas.isEmpty
            }
        }
    }

    func removeAnimationMetadata(for id: AnimationIdentifier) {
        queue.async(flags: .barrier) {
            var updatedMetas = self.metadatas
            updatedMetas.removeValue(forKey: id)
            DispatchQueue.main.async {
                self.metadatas = updatedMetas
                self.empty = updatedMetas.isEmpty
            }
        }
    }

    public func reload(with metadatas: [AnimationMetadata]) {
        queue.async(flags: .barrier) {
            let reloadedMetadatas = Dictionary(uniqueKeysWithValues: metadatas.map { ($0.id, $0) })
            DispatchQueue.main.async {
                self.metadatas = reloadedMetadatas
                self.empty = reloadedMetadatas.isEmpty
            }
        }
    }

    public func getById(id: AnimationIdentifier) -> Result<AnimationMetadata, ServerError> {
        queue.sync {
            if let metadata = metadatas[id] {
                return .success(metadata)
            } else {
                logger.warning("getById() called on an ID that wasn't in the cache! \(id)")
                return .failure(.notFound("Animation ID \(id) not found in the cache"))
            }
        }
    }

    public func fetchMetadataListFromServer() -> Result<String, ServerError> {

        let server = CreatureServerClient.shared

        Task {
            logger.info("attempting to fetch the animation metadata list from the server")
            let fetchResult = await server.listAnimations()
            switch(fetchResult) {
                case .success(let metadataList):
                    logger.debug("pulled \(metadataList.count) metadata from the server")
                    self.reload(with: metadataList)
                case .failure(let error):
                    logger.warning("Unable to fetch the list of animation metadata")
                    DispatchQueue.main.async {
                        AppState.shared.systemAlertMessage = error.localizedDescription
                        AppState.shared.showSystemAlert = true
                    }
            }

        }
        return .success("done")
    }
}

