import Common
import OSLog
import SwiftUI
import UniformTypeIdentifiers

#if os(iOS) || os(macOS)

    /// Anything the server can hand us as one shareable audio file: a sound's MP3
    /// rendition, a whole streamed exchange, whatever comes next. The request knows
    /// how to download itself and what content type the save panel should offer.
    protocol ShareableAudioRequest: Equatable, Sendable {
        var contentType: UTType { get }
        func download(using server: CreatureServerClient) async -> Result<
            CreatureServerClient.ShareableSound, ServerError
        >
    }

    /// The one shared implementation of the "Generate Shareable Version" flow: download
    /// the audio from the server, then prompt to save it to disk.
    ///
    /// Attach `.shareableAudioFlow(request:)` (or the sound-specific
    /// `.shareableSoundFlow(fileName:)`) once to a *stable* ancestor view and set the
    /// binding to kick things off. (Context-menu content is transient and can't present
    /// sheets, which is why the flow lives on the ancestor and menu items just set the
    /// binding — use `ShareableSoundButton` / `ShareableAudioButton` for those.)
    private struct ShareableAudioFlow<Request: ShareableAudioRequest>: ViewModifier {

        @Binding var request: Request?

        private let logger = Logger(
            subsystem: "io.opsnlops.CreatureConsole", category: "ShareableAudioFlow")
        private let server = CreatureServerClient.shared

        @State private var isWorking = false
        @State private var exportData: Data? = nil
        @State private var exportFilename = "sound.mp3"
        @State private var exportContentType: UTType = .mp3
        @State private var showExporter = false
        @State private var errorAlert: ErrorAlert?

        func body(content: Content) -> some View {
            content
                .onChange(of: request) { _, newValue in
                    guard let newValue else { return }
                    download(newValue)
                }
                .fileExporter(
                    isPresented: $showExporter,
                    document: AudioFileDocument(data: exportData ?? Data()),
                    contentType: exportContentType,
                    defaultFilename: exportFilename
                ) { result in
                    switch result {
                    case .success(let url):
                        logger.info("saved shareable audio to \(url.path)")
                    case .failure(let error):
                        errorAlert = ErrorAlert(
                            title: "Sharing Failed",
                            message: "Export failed: \(error.localizedDescription)")
                    }
                    exportData = nil
                    request = nil
                }
                .errorAlert($errorAlert) { request = nil }
        }

        private func download(_ audioRequest: Request) {
            guard !isWorking else { return }
            isWorking = true
            Task {
                let result = await audioRequest.download(using: server)
                await MainActor.run {
                    isWorking = false
                    switch result {
                    case .success(let shareable):
                        exportData = shareable.data
                        exportFilename = shareable.suggestedFilename
                        exportContentType = audioRequest.contentType
                        showExporter = true
                    case .failure(let error):
                        errorAlert = ErrorAlert(title: "Sharing Failed", error: error)
                    }
                }
            }
        }
    }

    extension View {
        /// Hosts a shareable-audio download/save flow. Setting the binding to a request
        /// downloads it and presents a save panel.
        func shareableAudioFlow<Request: ShareableAudioRequest>(
            request: Binding<Request?>
        ) -> some View {
            modifier(ShareableAudioFlow(request: request))
        }

        /// Hosts the shareable-sound download/save flow. Setting the binding to a sound
        /// file name downloads its MP3 rendition and presents a save panel. (The GUI
        /// shares MP3 — plays natively in AVFoundation and Slack; the Ogg/Opus rendition
        /// is CLI-only now.)
        func shareableSoundFlow(fileName: Binding<String?>) -> some View {
            shareableAudioFlow(
                request: Binding<SoundShareRequest?>(
                    get: {
                        fileName.wrappedValue.flatMap {
                            $0.isEmpty ? nil : SoundShareRequest(fileName: $0)
                        }
                    },
                    set: { fileName.wrappedValue = $0?.fileName }
                ))
        }
    }

    /// A stored sound's MP3 rendition, as `downloadSoundRendition` fetches it.
    struct SoundShareRequest: ShareableAudioRequest {
        let fileName: String

        var contentType: UTType { .mp3 }

        func download(using server: CreatureServerClient) async -> Result<
            CreatureServerClient.ShareableSound, ServerError
        > {
            await server.downloadSoundRendition(fileName: fileName, as: .mp3)
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

    /// The generic sibling of `ShareableSoundButton` for flows keyed by something
    /// richer than a file name (like an exchange + format). Same icon, same default
    /// title, same trigger-the-ancestor behavior.
    struct ShareableAudioButton<Request: ShareableAudioRequest>: View {
        let request: Request
        var title: String = "Generate Shareable Version…"
        @Binding var trigger: Request?

        var body: some View {
            Button {
                trigger = request
            } label: {
                Label(title, systemImage: "square.and.arrow.up")
            }
        }
    }

#else

    // tvOS has no save-to-disk story, so shared surfaces (like the ad-hoc sound and
    // exchange lists) compile against no-ops there and the feature simply doesn't appear.
    protocol ShareableAudioRequest: Equatable, Sendable {}

    extension View {
        func shareableAudioFlow<Request: ShareableAudioRequest>(
            request: Binding<Request?>
        ) -> some View {
            self
        }

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

    struct ShareableAudioButton<Request: ShareableAudioRequest>: View {
        let request: Request
        var title: String = "Generate Shareable Version…"
        @Binding var trigger: Request?

        var body: some View {
            EmptyView()
        }
    }

#endif
