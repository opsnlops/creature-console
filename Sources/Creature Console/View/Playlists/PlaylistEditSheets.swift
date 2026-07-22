// PlaylistEditSheets.swift
// Extracted from PlaylistsTable.swift (Phase 5 decomposition, issue #35).

import Common
import Foundation
import SwiftData
import SwiftUI

struct EditPlaylistSheet: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \AnimationMetadataModel.title, order: .forward)
    private var animations: [AnimationMetadataModel]

    @Binding var playlist: Common.Playlist?
    let onSave: (Common.Playlist) -> Void
    let onCancel: () -> Void

    @State private var editablePlaylist: Common.Playlist?
    @State private var showingAddAnimation = false
    @State private var refreshID = UUID()  // Forces SwiftUI to refresh when playlist changes

    var body: some View {
        Group {
            if let currentPlaylist = editablePlaylist {
                NavigationStack {
                    ScrollView {
                        // Sibling glass cards share one container so they blend as a cluster
                        GlassEffectContainer(spacing: 20) {
                            VStack(spacing: 20) {
                                // Header with editable name
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        TextField(
                                            "Playlist Name",
                                            text: Binding(
                                                get: { editablePlaylist?.name ?? "" },
                                                set: { newName in
                                                    editablePlaylist?.name = newName
                                                }
                                            )
                                        )
                                        .textFieldStyle(.roundedBorder)
                                        .font(.title2)

                                        Spacer()

                                        Text(
                                            "Total Weight: \(totalWeight(for: editablePlaylist ?? currentPlaylist))"
                                        )
                                        .foregroundStyle(.secondary)
                                        .font(.caption)
                                    }

                                    Text(
                                        "Items: \((editablePlaylist ?? currentPlaylist).items.count)"
                                    )
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                                }
                                .id(refreshID)  // Refresh when playlist changes
                                .padding()
                                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))

                                // Add Animation Button
                                HStack {
                                    Text("Animations")
                                        .font(.headline)

                                    Spacer()

                                    Button("Add Animation") {
                                        showingAddAnimation = true
                                    }
                                    .buttonStyle(.glassProminent)
                                }

                                // Animation List
                                if currentPlaylist.items.isEmpty {
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
                                    LazyVStack(spacing: 8) {
                                        ForEach(
                                            Array((editablePlaylist?.items ?? []).enumerated()),
                                            id: \.offset
                                        ) { index, item in
                                            EditablePlaylistItemRow(
                                                item: item,
                                                animationName: animationName(for: item.animationId),
                                                currentPlaylist: editablePlaylist
                                                    ?? currentPlaylist,
                                                onWeightChanged: { newWeight in
                                                    editablePlaylist?.items[index].weight =
                                                        newWeight
                                                    refreshID = UUID()  // Trigger UI refresh
                                                },
                                                onDelete: {
                                                    editablePlaylist?.items.remove(at: index)
                                                    refreshID = UUID()  // Trigger UI refresh
                                                }
                                            )
                                        }
                                    }
                                    .id(refreshID)  // Force refresh when refreshID changes
                                    .padding()
                                    .glassEffect(
                                        .regular.interactive(), in: .rect(cornerRadius: 12))
                                }
                            }
                            .padding()
                        }
                    }
                    .navigationTitle("Edit Playlist")
                    .safeAreaInset(edge: .bottom) {
                        // Compact floating glass capsule, trailing like a standard sheet's
                        // action buttons — not an edge-to-edge bar.
                        HStack(spacing: 12) {
                            Button("Cancel") {
                                onCancel()
                            }
                            .buttonStyle(.glass)

                            Button("Save") {
                                if let playlist = editablePlaylist {
                                    onSave(playlist)
                                }
                            }
                            .buttonStyle(.glassProminent)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .glassEffect(.regular.interactive(), in: .capsule)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.horizontal)
                        .padding(.bottom, 10)
                    }
                    .sheet(isPresented: $showingAddAnimation) {
                        AddAnimationToEditPlaylistSheet(
                            availableAnimations: availableAnimations,
                            onAdd: { animationId, weight in
                                addAnimation(animationId: animationId, weight: weight)
                            }
                        )
                    }
                }
            } else {
                VStack {
                    Text("Loading playlist...")
                    ProgressView()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .onAppear {
            if editablePlaylist == nil {
                editablePlaylist = playlist
            }
        }
    }

    private var availableAnimations: [AnimationMetadata] {
        animations.map { $0.toDTO() }.filter { metadata in
            !(editablePlaylist?.items.contains { $0.animationId == metadata.id } ?? false)
        }.sorted { $0.title < $1.title }
    }

    private func addAnimation(animationId: AnimationIdentifier, weight: UInt32) {
        let newItem = PlaylistItem(animationId: animationId, weight: weight)
        editablePlaylist?.items.append(newItem)
        refreshID = UUID()  // Trigger UI refresh
    }

    private func animationName(for id: AnimationIdentifier) -> String {
        animations.first(where: { $0.id == id })?.title ?? "Unknown Animation"
    }

    private func totalWeight(for playlist: Common.Playlist) -> UInt32 {
        playlist.items.reduce(0) { $0 + $1.weight }
    }

    private func percentage(for item: PlaylistItem, in playlist: Common.Playlist) -> Double {
        let total = totalWeight(for: playlist)
        guard total > 0 else { return 0 }
        return Double(item.weight) / Double(total) * 100
    }
}

struct EditablePlaylistItemRow: View {
    let item: PlaylistItem
    let animationName: String
    let currentPlaylist: Common.Playlist
    let onWeightChanged: (UInt32) -> Void
    let onDelete: () -> Void

    @State private var editingWeight: String = ""
    @State private var isEditingWeight = false

    private var percentage: Double {
        let totalWeight = currentPlaylist.items.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0 else { return 0 }
        return Double(item.weight) / Double(totalWeight) * 100
    }

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
                        .help("Save the new weight")
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
        if let newWeight = UInt32(editingWeight), newWeight > 0 {
            onWeightChanged(newWeight)
        }
        isEditingWeight = false
    }
}

struct AddAnimationToEditPlaylistSheet: View {
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
        NavigationStack {
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
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))

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
                    .disabled(
                        selectedAnimation == nil || weight.isEmpty || UInt32(weight) == nil
                            || UInt32(weight) == 0)
                }
            }
        }
        .frame(minWidth: 600, minHeight: 500)
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
