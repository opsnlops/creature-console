

import Foundation

enum AudioError : Error {
    case fileNotFound(String)
    case noAccess(String)
    case systemError(String)
}
