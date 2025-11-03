#if os(macOS)
    import AppKit
    import Common
    import Foundation
    import UniformTypeIdentifiers

    private struct ProgressAlert {
        let alert: NSAlert
        let indicator: NSProgressIndicator
    }

    enum LipSyncUtilities {

        @MainActor
        static func generateLipSyncFromWAV() {
            let panel = NSOpenPanel()
            panel.title = "Generate Lip Sync from WAV"
            panel.allowedContentTypes = [.wav]
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false
            panel.canChooseFiles = true
            panel.prompt = "Generate"

            panel.begin { response in
                guard response == .OK, let selectedURL = panel.url else { return }
                Task {
                    await processSelectedWAV(at: selectedURL)
                }
            }
        }

        private static func processSelectedWAV(at url: URL) async {
            let fileName = url.lastPathComponent

            let wavData: Data
            do {
                wavData = try Data(contentsOf: url)
            } catch {
                await presentSystemAlert(
                    message: "Failed to read the selected file: \(error.localizedDescription)")
                return
            }

            var progressAlert = await MainActor.run {
                presentProgressAlert(message: "Submitting lip sync job for \(fileName)…")
            }

            let result = await CreatureServerClient.shared.generateLipSyncUpload(
                fileName: fileName,
                wavData: wavData
            )

            switch result {
            case .success(let response):
                await MainActor.run {
                    updateProgressAlert(
                        progressAlert,
                        message: "Server responded. Preparing save dialog…"
                    )
                    dismissProgressAlert(progressAlert)
                    progressAlert = nil
                }
                await handleSuccessfulGeneration(
                    response: response,
                    originalFileURL: url
                )
            case .failure(let error):
                await MainActor.run {
                    dismissProgressAlert(progressAlert)
                    progressAlert = nil
                }
                await presentSystemAlert(
                    message: ServerError.detailedMessage(from: error))
            }
        }

        @MainActor
        private static func handleSuccessfulGeneration(
            response: LipSyncUploadResponse,
            originalFileURL: URL
        ) async {
            let defaultFileName = makeDefaultFileName(
                originalURL: originalFileURL,
                suggested: response.suggestedFilename
            )

            guard let destinationURL = promptForSaveLocation(defaultFileName: defaultFileName)
            else {
                return
            }

            do {
                try response.data.write(to: destinationURL, options: .atomic)
                await presentSystemAlert(
                    message: "Saved lip sync data to \(destinationURL.lastPathComponent).")
            } catch {
                await presentSystemAlert(
                    message: "Failed to save the lip sync file: \(error.localizedDescription)")
            }
        }

        @MainActor
        private static func promptForSaveLocation(defaultFileName: String) -> URL? {
            let panel = NSSavePanel()
            panel.title = "Save Lip Sync JSON"
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = defaultFileName
            panel.canCreateDirectories = true
            panel.prompt = "Save"

            return panel.runModal() == .OK ? panel.url : nil
        }

        private static func makeDefaultFileName(originalURL: URL, suggested: String?) -> String {
            if let suggested, !suggested.isEmpty {
                return suggested
            }

            let baseName = originalURL.deletingPathExtension().lastPathComponent
            return baseName.isEmpty ? "lipsync.json" : "\(baseName).json"
        }

        private static func presentSystemAlert(message: String) async {
            await AppState.shared.setSystemAlert(show: true, message: message)
        }

        @MainActor
        private static func presentProgressAlert(message: String) -> ProgressAlert? {
            guard let parentWindow = NSApp.keyWindow ?? NSApp.mainWindow else { return nil }

            let alert = NSAlert()
            alert.messageText = "Generating Lip Sync"
            alert.informativeText = message
            alert.alertStyle = .informational

            let indicator = NSProgressIndicator(frame: NSRect(x: 0, y: 0, width: 32, height: 32))
            indicator.style = .spinning
            indicator.controlSize = .regular
            indicator.startAnimation(nil)
            alert.accessoryView = indicator

            alert.beginSheetModal(for: parentWindow) { _ in }

            return ProgressAlert(alert: alert, indicator: indicator)
        }

        @MainActor
        private static func updateProgressAlert(_ progress: ProgressAlert?, message: String) {
            progress?.alert.informativeText = message
        }

        @MainActor
        private static func dismissProgressAlert(_ progress: ProgressAlert?) {
            guard let progress else { return }
            if let sheetParent = progress.alert.window.sheetParent {
                sheetParent.endSheet(progress.alert.window)
            } else {
                progress.alert.window.orderOut(nil)
            }
        }
    }
#endif
