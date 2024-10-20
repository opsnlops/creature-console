import Foundation

public enum AudioError: Error {
    case fileNotFound(String)
    case noAccess(String)
    case systemError(String)
    case failedToLoad(String)
}
