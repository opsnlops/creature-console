import Common
import OSLog
import SwiftUI
import UniformTypeIdentifiers

#if os(iOS) || os(macOS)

    /// The one shared implementation of the "Generate Shareable Version" flow: download
    /// the MP3 rendition from the server, then prompt to save it to disk.
    ///
    /// The GUI shares MP3 (plays natively in AVFoundation and Slack); the Ogg/Opus rendition is
    /// CLI-only now. Attach `.shareableSoundFlow(fileName:)` once to a *stable* ancestor view and
    /// set the binding to a sound file name to kick things off. (Context-menu content is transient
    /// and can't present sheets, which is why the flow lives on the ancestor and menu items just
    /// set the binding — use `ShareableSoundButton` for those.)
    private struct ShareableSoundFlow: ViewModifier {

        @Binding var fileName: String?

        private let logger = Logger(
            subsystem: "io.opsnlops.CreatureConsole", category: "ShareableSoundFlow")
        private let server = CreatureServerClient.shared

        @State private var isWorking = false
        @State private var exportData: Data? = nil
        @State private var exportFilename = "sound.mp3"
        @State private var showExporter = false
        @State private var errorAlert: ErrorAlert?

        func body(content: Content) -> some View {
            content
                .onChange(of: fileName) { _, newValue in
                    guard let newValue, !newValue.isEmpty else { return }
                    download(newValue)
                }
                .fileExporter(
                    isPresented: $showExporter,
                    document: AudioFileDocument(data: exportData ?? Data()),
                    contentType: .mp3,
                    defaultFilename: exportFilename
                ) { result in
                    switch result {
                    case .success(let url):
                        logger.info("saved shareable MP3 to \(url.path)")
                    case .failure(let error):
                        errorAlert = ErrorAlert(
                            title: "Sharing Failed",
                            message: "Export failed: \(error.localizedDescription)")
                    }
                    exportData = nil
                    fileName = nil
                }
                .errorAlert($errorAlert) { fileName = nil }
        }

        private func download(_ name: String) {
            guard !isWorking else { return }
            isWorking = true
            Task {
                let result = await server.downloadSoundRendition(fileName: name, as: .mp3)
                await MainActor.run {
                    isWorking = false
                    switch result {
                    case .success(let shareable):
                        exportData = shareable.data
                        exportFilename = shareable.suggestedFilename
                        showExporter = true
                    case .failure(let error):
                        errorAlert = ErrorAlert(title: "Sharing Failed", error: error)
                    }
                }
            }
        }
    }

    extension View {
        /// Hosts the shareable-sound download/save flow. Setting the binding to a sound
        /// file name downloads its Ogg/Opus rendition and presents a save panel.
        func shareableSoundFlow(fileName: Binding<String?>) -> some View {
            modifier(ShareableSoundFlow(fileName: fileName))
        }
    }

    /// A menu-item / button label that triggers a `shareableSoundFlow` hosted on an
    /// ancestor view. Keeps every surface's icon and behavior identical; the title is
    /// adjustable so surfaces that aren't obviously "a sound" (like an animation row)
    /// can say what's actually being shared.
    struct ShareableSoundButton: View {
        let fileName: String
        var title: String = "Generate Shareable Version…"
        @Binding var trigger: String?

        var body: some View {
            Button {
                trigger = fileName
            } label: {
                Label(title, systemImage: "square.and.arrow.up")
            }
            .disabled(fileName.isEmpty)
        }
    }

#else

    // tvOS has no save-to-disk story, so shared surfaces (like the ad-hoc sound list)
    // compile against no-ops there and the feature simply doesn't appear.
    extension View {
        func shareableSoundFlow(fileName: Binding<String?>) -> some View {
            self
        }
    }

    struct ShareableSoundButton: View {
        let fileName: String
        var title: String = "Generate Shareable Version…"
        @Binding var trigger: String?

        var body: some View {
            EmptyView()
        }
    }

#endif
