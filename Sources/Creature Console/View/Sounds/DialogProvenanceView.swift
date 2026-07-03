import Common
import SwiftUI

#if os(iOS) || os(macOS)

    /// A DialogProvenance paired with the file it came from, so it can drive a
    /// `.sheet(item:)` (DialogProvenance itself has no natural identity).
    struct IdentifiedProvenance: Identifiable {
        let id = UUID()
        let fileName: String
        let provenance: DialogProvenance
    }

    /// Shows what an otherwise-anonymous dialog render actually is: its source
    /// script, channel layout, and the full rendered script text (server #47).
    struct DialogProvenanceView: View {
        let fileName: String
        let provenance: DialogProvenance

        @Environment(\.dismiss) private var dismiss

        var body: some View {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        summaryCard
                        if !provenance.tracks.isEmpty {
                            tracksCard
                        }
                        if !provenance.scriptLines.isEmpty {
                            scriptCard
                        }
                    }
                    .padding()
                }
                .navigationTitle(provenance.title.isEmpty ? "Provenance" : provenance.title)
                #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                            .buttonStyle(.glassProminent)
                    }
                }
            }
        }

        // MARK: - Cards

        private var summaryCard: some View {
            card {
                VStack(alignment: .leading, spacing: 10) {
                    Label(fileName, systemImage: "waveform")
                        .font(.headline)
                        .textSelection(.enabled)

                    if !provenance.sourceScriptId.isEmpty {
                        infoRow("Script ID", provenance.sourceScriptId)
                    }
                    if !provenance.generationIds.isEmpty {
                        infoRow("Generations", provenance.generationIds.joined(separator: ", "))
                    }
                    if provenance.sourceScriptId.isEmpty && provenance.generationIds.isEmpty {
                        Text("No source script recorded for this render.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }

        private var tracksCard: some View {
            card {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Channels")
                        .font(.headline)
                    ForEach(provenance.tracks) { track in
                        HStack(spacing: 12) {
                            Text("\(track.channel)")
                                .font(.system(.body, design: .monospaced))
                                .frame(width: 28, alignment: .trailing)
                                .foregroundStyle(.secondary)
                            Text(track.name)
                            Spacer()
                        }
                    }
                }
            }
        }

        private var scriptCard: some View {
            card {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Script")
                        .font(.headline)
                    ForEach(Array(provenance.scriptLines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(.callout, design: .rounded))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }

        // MARK: - Building blocks

        private func infoRow(_ label: String, _ value: String) -> some View {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 96, alignment: .leading)
                Text(value)
                    .font(.system(.subheadline, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }

        private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
            content()
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(.regular, in: .rect(cornerRadius: 16))
        }
    }

#endif
