import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// Ogg container audio (the server's shareable Opus downloads). The SDK ships no
    /// Ogg type, so we derive one from the file extension.
    static let oggAudio = UTType(filenameExtension: "ogg", conformingTo: .audio) ?? .audio
}

/// A trivial `FileDocument` wrapper around raw audio bytes so any panel can use SwiftUI's
/// cross-platform `.fileExporter` to save server-produced audio — mono / 17-channel WAVs
/// for Audacity, MP3 shareable versions (the GUI's share format), Ogg/Opus, and whatever
/// comes next.
struct AudioFileDocument: FileDocument {

    static var readableContentTypes: [UTType] { [.wav, .mp3, .oggAudio] }
    static var writableContentTypes: [UTType] { [.wav, .mp3, .oggAudio] }

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
