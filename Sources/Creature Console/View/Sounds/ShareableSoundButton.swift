import Common
import OSLog
import SwiftUI
import UniformTypeIdentifiers

#if os(iOS) || os(macOS)

    /// The one shared implementation of the "Generate Shareable Version" flow: download
    /// the Ogg/Opus rendition from the server, then prompt to save it to disk.
    ///
    /// Attach `.shareableSoundFlow(fileName:)` once to a *stable* ancestor view and set
    /// the binding to a sound file name to kick things off. (Context-menu content is
    /// transient and can't present sheets, which is why the flow lives on the ancestor
    /// and menu items just set the binding — use `ShareableSoundButton` for those.)
    private struct ShareableSoundFlow: ViewModifier {

        @Binding var fileName: String?

        private let logger = Logger(
            subsystem: "io.opsnlops.CreatureConsole", category: "ShareableSoundFlow")
        private let server = CreatureServerClient.shared

        @State private var isWorking = false
        @State private var exportData: Data? = nil
        @State private var exportFilename = "sound.ogg"
        @State private var showExporter = false
        @State private var showError = false
        @State private var errorMessage = ""

        func body(content: Content) -> some View {
            content
                .onChange(of: fileName) { _, newValue in
                    guard let newValue, !newValue.isEmpty else { return }
                    download(newValue)
                }
                .fileExporter(
                    isPresented: $showExporter,
                    document: AudioFileDocument(data: exportData ?? Data()),
                    contentType: .oggAudio,
                    defaultFilename: exportFilename
                ) { result in
                    switch result {
                    case .success(let url):
                        logger.info("saved shareable sound to \(url.path)")
                    case .failure(let error):
                        presentError("Export failed: \(error.localizedDescription)")
                    }
                    exportData = nil
                    fileName = nil
                }
                .alert("Sharing Failed", isPresented: $showError) {
                    Button("OK") { fileName = nil }
                } message: {
                    Text(errorMessage)
                }
        }

        private func download(_ name: String) {
            guard !isWorking else { return }
            isWorking = true
            Task {
                let result = await server.downloadShareableSound(fileName: name)
                await MainActor.run {
                    isWorking = false
                    switch result {
                    case .success(let shareable):
                        exportData = shareable.data
                        exportFilename = shareable.suggestedFilename
                        showExporter = true
                    case .failure(let error):
                        presentError(ServerError.detailedMessage(from: error))
                    }
                }
            }
        }

        private func presentError(_ message: String) {
            errorMessage = message
            showError = true
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
    /// ancestor view. Keeps every surface's wording and icon identical.
    struct ShareableSoundButton: View {
        let fileName: String
        @Binding var trigger: String?

        var body: some View {
            Button {
                trigger = fileName
            } label: {
                Label("Generate Shareable Version…", systemImage: "square.and.arrow.up")
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
        @Binding var trigger: String?

        var body: some View {
            EmptyView()
        }
    }

#endif
