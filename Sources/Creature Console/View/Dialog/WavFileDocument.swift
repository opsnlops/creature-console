import SwiftUI
import UniformTypeIdentifiers

/// A trivial `FileDocument` wrapper around raw WAV bytes so the dialog preview panel can use
/// SwiftUI's cross-platform `.fileExporter` to save mono / 17-channel WAVs for Audacity.
struct WavFileDocument: FileDocument {

    static var readableContentTypes: [UTType] { [.wav] }
    static var writableContentTypes: [UTType] { [.wav] }

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
