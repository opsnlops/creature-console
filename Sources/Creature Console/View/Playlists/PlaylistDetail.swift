import Common
import OSLog
import SwiftUI

struct PlaylistDetail: View {
    @Binding var playlist: Common.Playlist

    @State private var editingName: String = ""
    @State private var showingAddAnimation = false
    @State private var selectedAnimationId: AnimationIdentifier? = nil
    @State private var newWeight: String = "1"
    @State private var showErrorAlert = false
    @State private var alertMessage = ""

    @State private var animationCacheState = AnimationMetadataCacheState(
        metadatas: [:], empty: true)

    private let logger = Logger(
        subsystem: "io.opsnlops.CreatureConsole", category: "PlaylistDetail")

    var totalWeight: UInt32 {
        playlist.items.reduce(0) { $0 + $1.weight }
    }

    var body: some View {
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
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))

            // Weight Distribution Visualization
            if !playlist.items.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Weight Distribution")
                        .font(.headline)

                    WeightDistributionView(
                        items: playlist.items, animationCacheState: animationCacheState)
                }
                .padding()
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
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
                    .buttonStyle(.borderedProminent)
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
                        .buttonStyle(.borderedProminent)
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
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))

            Spacer()
        }
        .padding()
        .task {
            for await state in await AnimationMetadataCache.shared.stateUpdates {
                await MainActor.run {
                    animationCacheState = state
                }
            }
        }
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
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK") {}
        } message: {
            Text(alertMessage)
        }
    }

    private var availableAnimations: [AnimationMetadata] {
        animationCacheState.metadatas.values.filter { metadata in
            !playlist.items.contains { $0.animationId == metadata.id }
        }.sorted { $0.title < $1.title }
    }

    private func animationName(for id: AnimationIdentifier) -> String {
        animationCacheState.metadatas[id]?.title ?? "Unknown Animation"
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

struct PlaylistItemRow: View {
    let item: PlaylistItem
    let animationName: String
    let percentage: Double
    let onWeightChanged: (UInt32) -> Void
    let onDelete: () -> Void

    @State private var editingWeight: String = ""
    @State private var isEditingWeight = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(animationName)
                    .font(.headline)

                Text("ID: \(item.animationId)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 8) {
                    if isEditingWeight {
                        TextField("Weight", text: $editingWeight)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                            .onSubmit {
                                submitWeightChange()
                            }

                        Button("✓") {
                            submitWeightChange()
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.green)
                    } else {
                        Text("Weight: \(item.weight)")
                            .font(.subheadline)
                            .onTapGesture {
                                startEditingWeight()
                            }
                    }
                }

                Text(String(format: "%.1f%%", percentage))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button("Delete") {
                onDelete()
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.red)
        }
        .padding(.vertical, 8)
        .contextMenu {
            Button("Edit Weight") {
                startEditingWeight()
            }

            Divider()

            Button("Delete", role: .destructive) {
                onDelete()
            }
        }
    }

    private func startEditingWeight() {
        editingWeight = String(item.weight)
        isEditingWeight = true
    }

    private func submitWeightChange() {
        if let newWeight = UInt32(editingWeight) {
            onWeightChanged(newWeight)
        }
        isEditingWeight = false
    }
}

struct WeightDistributionView: View {
    let items: [PlaylistItem]
    let animationCacheState: AnimationMetadataCacheState

    private var totalWeight: UInt32 {
        items.reduce(0) { $0 + $1.weight }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                ForEach(items, id: \.id) { item in
                    let percentage = totalWeight > 0 ? Double(item.weight) / Double(totalWeight) : 0

                    Rectangle()
                        .fill(colorForAnimation(item.animationId))
                        .frame(width: max(percentage * 300, 4))
                        .help(
                            "\(animationName(for: item.animationId)): \(String(format: "%.1f%%", percentage * 100))"
                        )
                }
            }
            .frame(height: 20)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200))], spacing: 8) {
                ForEach(items, id: \.id) { item in
                    let percentage =
                        totalWeight > 0 ? Double(item.weight) / Double(totalWeight) * 100 : 0

                    HStack(spacing: 8) {
                        Rectangle()
                            .fill(colorForAnimation(item.animationId))
                            .frame(width: 12, height: 12)
                            .clipShape(RoundedRectangle(cornerRadius: 2))

                        Text(animationName(for: item.animationId))
                            .font(.caption)
                            .lineLimit(1)

                        Spacer()

                        Text(String(format: "%.1f%%", percentage))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func animationName(for id: AnimationIdentifier) -> String {
        animationCacheState.metadatas[id]?.title ?? "Unknown"
    }

    private func colorForAnimation(_ id: AnimationIdentifier) -> Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .red, .pink, .indigo, .teal]
        let hash = abs(id.hashValue)
        return colors[hash % colors.count]
    }
}

struct AddAnimationToPlaylistView: View {
    let availableAnimations: [AnimationMetadata]
    let onAdd: (AnimationIdentifier, UInt32) -> Void

    @State private var selectedAnimation: AnimationMetadata?
    @State private var weight: String = "1"
    @State private var searchText = ""

    @Environment(\.dismiss) private var dismiss

    private var filteredAnimations: [AnimationMetadata] {
        if searchText.isEmpty {
            return availableAnimations
        } else {
            return availableAnimations.filter {
                $0.title.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Weight")
                        .font(.headline)

                    TextField("Enter weight (1-999)", text: $weight)
                        .textFieldStyle(.roundedBorder)

                    Text("Higher weights make animations more likely to be selected.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 8) {
                    Text("Select Animation")
                        .font(.headline)

                    if availableAnimations.isEmpty {
                        ContentUnavailableView {
                            Label("No Available Animations", systemImage: "music.note")
                        } description: {
                            Text("All animations are already in this playlist.")
                        }
                    } else {
                        List(filteredAnimations, id: \.id, selection: $selectedAnimation) {
                            animation in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(animation.title)
                                    .font(.headline)

                                Text(
                                    "Frames: \(animation.numberOfFrames) • Duration: \(animation.millisecondsPerFrame)ms/frame"
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)

                                if !animation.note.isEmpty {
                                    Text(animation.note)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .italic()
                                }
                            }
                            .padding(.vertical, 4)
                            .tag(animation)
                        }
                        .searchable(text: $searchText, prompt: "Search animations...")
                    }
                }
            }
            .padding()
            .navigationTitle("Add Animation")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addAnimation()
                    }
                    .disabled(selectedAnimation == nil || weight.isEmpty || UInt32(weight) == nil)
                }
            }
        }
    }

    private func addAnimation() {
        guard let animation = selectedAnimation,
            let weightValue = UInt32(weight),
            weightValue > 0
        else {
            return
        }

        onAdd(animation.id, weightValue)
        dismiss()
    }
}

#Preview {
    PlaylistDetail(playlist: .constant(Common.Playlist.mock()))
}
