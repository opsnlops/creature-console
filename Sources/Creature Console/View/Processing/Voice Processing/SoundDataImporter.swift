import Common
import Foundation
import OSLog
import SwiftUI
import UniformTypeIdentifiers

struct SoundDataImport: View {

    @State private var jsonString: String = ""
    @State private var isFileImporterPresented: Bool = false

    @State private var errorAlert: ErrorAlert?
    @AppStorage("mouthImportDefaultAxis") private var selectedAxis: Int = 2
    @State private var successBanner: String?

    var soundDataProcessor = SoundDataProcessor()
    @Binding var track: Track
    var millisecondsPerFrame: UInt32

    private var frameWidth: Int { track.frames.first?.count ?? 0 }

    let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "SoundDataImport")

    var body: some View {
        GlassEffectContainer(spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Replace Axis")
                        .font(.headline)
                    Picker("Axis", selection: $selectedAxis) {
                        ForEach(0..<(max(frameWidth, 1)), id: \.self) { idx in
                            Text("\(idx)").tag(idx)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 320)
                    .disabled(frameWidth == 0)
                }

                HStack {
                    Spacer()
                    Button {
                        isFileImporterPresented = true
                    } label: {
                        Label(
                            "Import Mouth Data to Axis \(selectedAxis)",
                            systemImage: "arrow.down.doc")
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .tint(.accentColor)
                    Spacer()
                }
                .fileImporter(
                    isPresented: $isFileImporterPresented,
                    allowedContentTypes: [UTType.json],
                    allowsMultipleSelection: false
                ) { result in
                    switch result {
                    case .success(let urls):
                        guard let url = urls.first else {
                            presentError("No file selected.")
                            return
                        }

                        let accessGranted = url.startAccessingSecurityScopedResource()
                        defer { if accessGranted { url.stopAccessingSecurityScopedResource() } }

                        do {
                            let jsonData = try Data(contentsOf: url)
                            jsonString = String(data: jsonData, encoding: .utf8) ?? ""

                            let decoder = JSONDecoder()
                            do {
                                let soundData = try decoder.decode(SoundData.self, from: jsonData)
                                logger.info("Imported mouth data JSON")
                                Task {
                                    let replaceResult =
                                        soundDataProcessor.replaceAxisDataWithSoundData(
                                            soundData: soundData,
                                            axis: selectedAxis,
                                            track: track,
                                            millisecondsPerFrame: millisecondsPerFrame
                                        )
                                    switch replaceResult {
                                    case .success(let updatedTrack):
                                        track = updatedTrack
                                        successBanner =
                                            "Imported mouth data and replaced axis \(selectedAxis) (\(updatedTrack.frames.count) frames)."
                                    case .failure(let error):
                                        logger.warning(
                                            "Failed to update track: \(error.localizedDescription)")
                                        presentError(
                                            "Failed to update track: \(error.localizedDescription)"
                                        )
                                    }
                                }
                            } catch {
                                logger.warning(
                                    "Failed to decode JSON: \(error.localizedDescription)")
                                presentError(
                                    "Failed to decode JSON: \(error.localizedDescription)")
                            }
                        } catch {
                            logger.warning("Unable to open file: \(error.localizedDescription)")
                            presentError("Unable to open file: \(error.localizedDescription)")
                        }

                    case .failure(let error):
                        logger.warning("File import failed: \(error.localizedDescription)")
                        presentError("File import failed: \(error.localizedDescription)")
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: 420)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 8)
        .task {
            let width = frameWidth
            if width > 0, selectedAxis >= width { selectedAxis = max(0, width - 1) }
        }
        .statusBanner($successBanner, duration: .seconds(1.5), alignment: .top)
        .errorAlert($errorAlert, dismissLabel: "Dismiss")
    }

    private func presentError(_ message: String) {
        errorAlert = ErrorAlert(title: "Mouth Data Import", message: message)
    }
}
