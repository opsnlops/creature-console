
import Foundation


public enum PlaylistErrors : Error {
    case communicationError(String)
    case dataFormatError(String)
    case otherError(String)
    case databaseError(String)
    case notFound(String)
}
