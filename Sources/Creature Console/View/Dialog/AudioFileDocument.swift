import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// Ogg container audio (the server's shareable Opus downloads). The SDK ships no
    /// Ogg type, so we derive one from the file extension.
    static let oggAudio = UTType(filenameExtension: "ogg", conformingTo: .audio) ?? .audio
}

/// A trivial `FileDocument` wrapper around raw audio bytes so any panel can use SwiftUI's
/// cross-platform `.fileExporter` to save server-produced audio — mono / 17-channel WAVs
/// for Audacity, Ogg/Opus shareable versions, and whatever comes next.
struct AudioFileDocument: FileDocument {

    static var readableContentTypes: [UTType] { [.wav, .oggAudio] }
    static var writableContentTypes: [UTType] { [.wav, .oggAudio] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
