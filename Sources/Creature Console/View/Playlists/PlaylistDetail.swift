import Common
import OSLog
import SwiftData
import SwiftUI

struct PlaylistDetail: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \AnimationMetadataModel.title, order: .forward)
    private var animations: [AnimationMetadataModel]

    @Binding var playlist: Common.Playlist

    @State private var editingName: String = ""
    @State private var showingAddAnimation = false
    @State private var selectedAnimationId: AnimationIdentifier? = nil
    @State private var newWeight: String = "1"

    private let logger = Logger(
        subsystem: "io.opsnlops.CreatureConsole", category: "PlaylistDetail")

    var totalWeight: UInt32 {
        playlist.items.reduce(0) { $0 + $1.weight }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // The header and weight-distribution cards are siblings in one glass
            // container so the adjacent surfaces blend and morph together.
            GlassEffectContainer(spacing: 20) {
                VStack(alignment: .leading, spacing: 20) {
                    // Playlist Header
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            TextField("Playlist Name", text: $editingName)
                                .textFieldStyle(.roundedBorder)
                                .font(.title2)
                                .onSubmit {
                                    updatePlaylistName()
                                }

                            Spacer()

                            Text("Total Weight: \(totalWeight)")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }

                        Text("Items: \(playlist.items.count)")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    .padding()
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))

                    // Weight Distribution Visualization
                    if !playlist.items.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Weight Distribution")
                                .font(.headline)

                            WeightDistributionView(items: playlist.items, animations: animations)
                        }
                        .padding()
                        .glassEffect(.regular, in: .rect(cornerRadius: 12))
                    }
                }
            }

            // Playlist Items
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Animations")
                        .font(.headline)

                    Spacer()

                    Button("Add Animation") {
                        showingAddAnimation = true
                    }
                    .buttonStyle(.glassProminent)
                }

                if playlist.items.isEmpty {
                    ContentUnavailableView {
                        Label("No Animations", systemImage: "music.note.list")
                    } description: {
                        Text("Add animations to create your playlist")
                    } actions: {
                        Button("Add Animation") {
                            showingAddAnimation = true
                        }
                        .buttonStyle(.glassProminent)
                    }
                } else {
                    List {
                        ForEach(Array(playlist.items.enumerated()), id: \.element.id) {
                            index, item in
                            PlaylistItemRow(
                                item: item,
                                animationName: animationName(for: item.animationId),
                                percentage: percentage(for: item),
                                onWeightChanged: { newWeight in
                                    updateWeight(at: index, weight: newWeight)
                                },
                                onDelete: {
                                    deleteItem(at: index)
                                }
                            )
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .padding()
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))

            Spacer()
        }
        .padding()
        .bottomToolbarInset()
        .onAppear {
            editingName = playlist.name
        }
        .sheet(isPresented: $showingAddAnimation) {
            AddAnimationToPlaylistView(
                availableAnimations: availableAnimations,
                onAdd: { animationId, weight in
                    addAnimation(animationId: animationId, weight: weight)
                }
            )
        }
    }

    private var availableAnimations: [AnimationMetadata] {
        animations.map { $0.toDTO() }.filter { metadata in
            !playlist.items.contains { $0.animationId == metadata.id }
        }.sorted { $0.title < $1.title }
    }

    private func animationName(for id: AnimationIdentifier) -> String {
        animations.first(where: { $0.id == id })?.title ?? "Unknown Animation"
    }

    private func percentage(for item: PlaylistItem) -> Double {
        guard totalWeight > 0 else { return 0 }
        return Double(item.weight) / Double(totalWeight) * 100
    }

    private func updatePlaylistName() {
        playlist.name = editingName
    }

    private func updateWeight(at index: Int, weight: UInt32) {
        guard index < playlist.items.count else { return }
        playlist.items[index].weight = weight
    }

    private func deleteItem(at index: Int) {
        guard index < playlist.items.count else { return }
        playlist.items.remove(at: index)
    }

    private func addAnimation(animationId: AnimationIdentifier, weight: UInt32) {
        let newItem = PlaylistItem(animationId: animationId, weight: weight)
        playlist.items.append(newItem)
    }
}

#Preview {
    PlaylistDetail(playlist: .constant(Common.Playlist.mock()))
}
