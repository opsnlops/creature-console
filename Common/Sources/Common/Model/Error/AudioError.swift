import Foundation

public enum AudioError: Error {
    case fileNotFound(String)
    case noAccess(String)
    case systemError(String)
    case failedToLoad(String)

    /// The human-readable detail carried by the case. Use this in the UI instead of
    /// `localizedDescription`, which — since this enum has no `LocalizedError` conformance —
    /// renders as a generic "operation couldn't be completed" and discards the payload string.
    public var message: String {
        switch self {
        case .fileNotFound(let message),
            .noAccess(let message),
            .systemError(let message),
            .failedToLoad(let message):
            return message
        }
    }
}

extension AudioError: LocalizedError {
    public var errorDescription: String? { message }
}
