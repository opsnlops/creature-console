import Combine
import Common
import Foundation
import OSLog

class AnimationMetadataCache: ObservableObject {
    static let shared = AnimationMetadataCache()

    @Published public private(set) var metadatas: [AnimationIdentifier: AnimationMetadata] = [:]
    @Published public private(set) var empty: Bool = true

    private let logger = Logger(
        subsystem: "io.opsnlops.CreatureConsole", category: "AnimationMetadataCache")
    private let queue = DispatchQueue(
        label: "io.opsnlops.CreatureConsole.AnimationMetadataCache.queue", attributes: .concurrent)

    private init() {}

    func addAnimationMetadata(_ metadata: AnimationMetadata, for id: AnimationIdentifier) {
        queue.async(flags: .barrier) {
            DispatchQueue.main.async {
                self.metadatas[id] = metadata
                self.empty = self.metadatas.isEmpty
            }
        }
    }

    func removeAnimationMetadata(for id: AnimationIdentifier) {
        queue.async(flags: .barrier) {
            DispatchQueue.main.async {
                self.metadatas.removeValue(forKey: id)
                self.empty = self.metadatas.isEmpty
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
            switch fetchResult {
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
