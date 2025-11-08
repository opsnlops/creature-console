import Foundation

public enum ServerError: Error, LocalizedError {
    case communicationError(String)
    case dataFormatError(String)
    case otherError(String)
    case databaseError(String)
    case notFound(String)
    case unknownError(String)
    case serverError(String)
    case websocketError(String)
    case notImplemented(String)
    case conflict(String)


    public var errorDescription: String? {
        switch self {
        case .communicationError(let message),
            .dataFormatError(let message),
            .otherError(let message),
            .databaseError(let message),
            .notFound(let message),
            .unknownError(let message),
            .serverError(let message),
            .websocketError(let message),
            .notImplemented(let message),
            .conflict(let message):
            return message
        }
    }

    /// Get detailed error message for UI display, with fallback for any Error type
    public static func detailedMessage(from error: Error) -> String {
        if let serverError = error as? ServerError {
            return serverError.errorDescription ?? "Unknown server error"
        }
        return error.localizedDescription
    }
}
