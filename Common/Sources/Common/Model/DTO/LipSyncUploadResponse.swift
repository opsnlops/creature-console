import Foundation

/// Response payload for lip sync generation from an uploaded WAV file.
public struct LipSyncUploadResponse: Sendable {

    /// Raw JSON data produced by Rhubarb Lip Sync.
    public let data: Data

    /// Suggested filename returned by the server (if provided).
    public let suggestedFilename: String?

    public init(data: Data, suggestedFilename: String?) {
        self.data = data
        self.suggestedFilename = suggestedFilename
    }
}
