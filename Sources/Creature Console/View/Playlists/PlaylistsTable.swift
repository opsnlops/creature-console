import Common
import Foundation
import OSLog
import SwiftData
import SwiftUI

#if os(iOS)
    import UIKit
#endif

struct PlaylistsTable: View {

    let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "PlaylistsTable")

    @Environment(\.modelContext) private var modelContext

    @Query(sort: \PlaylistModel.name, order: .forward)
    private var playlists: [PlaylistModel]

    // Our Server
    let server = CreatureServerClient.shared

    @State private var showErrorAlert = false
    @State private var showSuccessAlert = false
    @State private var alertMessage = ""
    @State private var successMessage = ""

    @State private var selection: PlaylistIdentifier? = nil
    @State private var editingPlaylist: Common.Playlist? = nil
    @State private var showingEditSheet = false
    @State private var showingCreateSheet = false

    @State private var playlistTask: Task<Void, Never>? = nil

    @AppStorage("activeUniverse") var activeUniverse: UniverseIdentifier = 1

    private var playlistTable: some View {
        Table(playlists, selection: $selection) {
            TableColumn("Name") { playlistModel in
                Text(playlistModel.name)
                    #if os(macOS)
                        .onTapGesture(count: 2) {
                            editPlaylist(playlistModel.toDTO())
                        }
                    #endif
            }
            .width(min: 300, ideal: 500)

            TableColumn("Items") { playlist in
                Text(playlist.items.count, format: .number)
            }
            .width(min: 80)

            TableColumn("Total Weight") { playlist in
                let totalWeight = playlist.items.reduce(0) { $0 + $1.weight }
                Text(totalWeight, format: .number)
            }
            .width(min: 100)

        }
        #if os(macOS)
            .contextMenu(forSelectionType: PlaylistIdentifier.self) {
                (items: Set<PlaylistIdentifier>) in
                if let playlistId = items.first ?? selection,
                    let playlistModel = playlists.first(where: { $0.id == playlistId })
                {
                    playlistContextMenu(for: playlistModel.toDTO())
                }
            }
        #else
            .contextMenu {
                if let playlistId = selection,
                    let playlistModel = playlists.first(where: { $0.id == playlistId })
                {
                    playlistContextMenu(for: playlistModel.toDTO())
                }
            }
        #endif
    }

    private func playlistContextMenu(for playlist: Common.Playlist) -> some View {
        Group {
            Button {
                editPlaylist(playlist)
            } label: {
                Label("Edit Playlist", systemImage: "pencil")
            }

            Divider()

            Button {
                playPlaylist(playlist)
            } label: {
                Label("Play Playlist", systemImage: "music.quarternote.3")
            }

        }
    }

    var body: some View {
        NavigationStack {
            VStack {
                if !playlists.isEmpty {
                    playlistTable
                } else {
                    ContentUnavailableView {
                        Label("No Playlists", systemImage: "music.note.list")
                    } description: {
                        Text("Create a playlist to get started")
                    } actions: {
                        Button(action: {
                            showingCreateSheet = true
                        }) {
                            Label("New Playlist", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }  // VStack
            .onChange(of: selection) {
                logger.debug("selection is now \(String(describing: selection))")
            }
            .alert("Error", isPresented: $showErrorAlert) {
                Button("Shit") {}
            } message: {
                Text(alertMessage)
            }
            .alert("Success", isPresented: $showSuccessAlert) {
                Button("OK") {}
            } message: {
                Text(successMessage)
            }
            .toolbar(id: "playlistList") {
                #if os(iOS)
                    ToolbarItem(id: "create", placement: .topBarTrailing) {
                        Button(action: {
                            showingCreateSheet = true
                        }) {
                            Image(systemName: "plus")
                        }
                    }

                    ToolbarItem(id: "edit", placement: .topBarTrailing) {
                        Button(action: {
                            if let selectedId = selection,
                                let playlistModel = playlists.first(where: { $0.id == selectedId })
                            {
                                editPlaylist(playlistModel.toDTO())
                            }
                        }) {
                            Image(systemName: "pencil")
                        }
                        .disabled(selection == nil)
                    }

                    ToolbarItem(id: "stop", placement: .topBarTrailing) {
                        Button(action: {
                            stopPlayback()
                        }) {
                            Image(systemName: "stop.circle")
                                .symbolRenderingMode(.palette)
                        }
                    }

                #else
                    ToolbarItem(id: "create", placement: .primaryAction) {
                        Button(action: {
                            showingCreateSheet = true
                        }) {
                            Image(systemName: "plus")
                        }
                    }

                    ToolbarItem(id: "edit", placement: .secondaryAction) {
                        Button(action: {
                            if let selectedId = selection,
                                let playlistModel = playlists.first(where: { $0.id == selectedId })
                            {
                                editPlaylist(playlistModel.toDTO())
                            }
                        }) {
                            Image(systemName: "pencil")
                        }
                        .disabled(selection == nil)
                    }

                    ToolbarItem(id: "stop", placement: .secondaryAction) {
                        Button(action: {
                            stopPlayback()
                        }) {
                            Image(systemName: "stop.circle")
                                .symbolRenderingMode(.palette)
                        }
                    }
                #endif
            }
            .navigationTitle("Playlists")
            #if os(macOS)
                .navigationSubtitle("Number of Playlists: \(playlists.count)")
            #endif
            .sheet(isPresented: $showingEditSheet) {
                EditPlaylistSheet(
                    playlist: $editingPlaylist,
                    onSave: { playlist in
                        logger.debug("Save button pressed in EditPlaylistSheet")
                        savePlaylist(playlist)
                    },
                    onCancel: {
                        logger.debug("Cancel button pressed in EditPlaylistSheet")
                        showingEditSheet = false
                    }
                )
            }
            .sheet(isPresented: $showingCreateSheet) {
                CreatePlaylistView { newPlaylist in
                    createPlaylist(newPlaylist)
                }
                .frame(width: 480, height: 400)
            }
        }  // Navigation Stack
    }  // View


    func editPlaylist(_ playlist: Common.Playlist) {
        editingPlaylist = playlist
        showingEditSheet = true
    }

    func updatePlaylist(_ updatedPlaylist: Common.Playlist) {
        editingPlaylist = updatedPlaylist
    }

    func savePlaylist(_ playlist: Common.Playlist) {
        logger.debug("savePlaylist called with playlist: \(playlist.name)")
        Task {
            let result = await server.updatePlaylist(playlist)
            await MainActor.run {
                switch result {
                case .success(let message):
                    logger.info("Playlist updated successfully: \(message)")
                    // Refresh from server
                    Task {
                        let container = await SwiftDataStore.shared.container()
                        let importer = PlaylistImporter(modelContainer: container)
                        let result = await server.getAllPlaylists()
                        switch result {
                        case .success(let list):
                            do {
                                try await importer.upsertBatch(list)
                                logger.debug("Cache refresh successful")
                            } catch {
                                logger.warning(
                                    "Cache refresh failed: \(error.localizedDescription)")
                            }
                        case .failure(let error):
                            logger.warning(
                                "Failed to fetch playlists: \(error.localizedDescription)")
                        }
                    }
                    // Clean up and close dialog
                    showingEditSheet = false
                    editingPlaylist = nil
                case .failure(let error):
                    let detailedError = ServerError.detailedMessage(from: error)
                    logger.error("Save failed with error: \(error)")
                    logger.error("Error type: \(type(of: error))")
                    alertMessage = "Failed to save playlist: \(detailedError)"
                    showErrorAlert = true
                    logger.error("Failed to save playlist: \(detailedError)")
                    logger.error(
                        "Playlist data: \(playlist.name) with \(playlist.items.count) items")
                }
            }
        }
    }

    func createPlaylist(_ playlist: Common.Playlist) {
        Task {
            let result = await server.createPlaylist(playlist)
            await MainActor.run {
                switch result {
                case .success:
                    logger.info("Playlist created successfully")
                    // Refresh from server
                    Task {
                        let container = await SwiftDataStore.shared.container()
                        let importer = PlaylistImporter(modelContainer: container)
                        let result = await server.getAllPlaylists()
                        switch result {
                        case .success(let list):
                            do {
                                try await importer.upsertBatch(list)
                                logger.debug("Cache refresh successful")
                            } catch {
                                logger.warning(
                                    "Cache refresh failed: \(error.localizedDescription)")
                            }
                        case .failure(let error):
                            logger.warning(
                                "Failed to fetch playlists: \(error.localizedDescription)")
                        }
                    }
                    showingCreateSheet = false
                case .failure(let error):
                    let detailedError = ServerError.detailedMessage(from: error)
                    alertMessage = "Failed to create playlist: \(detailedError)"
                    showErrorAlert = true
                    logger.error("Failed to create playlist: \(detailedError)")
                }
            }
        }
    }


    func playSelected() {
        logger.debug("Attempting to play the selected playlist on the active universe")

        // Go see what, if anything, is selected
        if let playlistId = selection {
            playPlaylistById(playlistId)
        }
    }

    func playPlaylist(_ playlist: Common.Playlist) {
        logger.debug("Attempting to play playlist '\(playlist.name)' on the active universe")
        playPlaylistById(playlist.id)
    }

    private func playPlaylistById(_ playlistId: PlaylistIdentifier) {
        playlistTask?.cancel()

        playlistTask = Task {
            let result = await server.startPlayingPlaylist(
                universe: activeUniverse, playlistId: playlistId)
            switch result {
            case .success(let message):
                await MainActor.run {
                    successMessage = message
                    showSuccessAlert = true
                    logger.info("Successfully started playlist: \(message)")
                }
            case .failure(let error):
                await MainActor.run {
                    let detailedError = ServerError.detailedMessage(from: error)
                    alertMessage = "Error starting playlist: \(detailedError)"
                    logger.warning("Unable to start a playlist: \(detailedError)")
                    showErrorAlert = true
                }
            }
        }
    }

    func stopPlayback() {

        logger.debug("Attempting to stop playing a playlist on the active universe")

        playlistTask?.cancel()

        playlistTask = Task {
            let result = await server.stopPlayingPlaylist(universe: activeUniverse)
            switch result {
            case .success(let message):
                await MainActor.run {
                    successMessage = message
                    showSuccessAlert = true
                    logger.info("Successfully stopped playlist playback: \(message)")
                }
            case .failure(let error):
                await MainActor.run {
                    let detailedError = ServerError.detailedMessage(from: error)
                    alertMessage = "Error stopping playlist: \(detailedError)"
                    logger.warning("Unable to stop playlist playback: \(detailedError)")
                    showErrorAlert = true
                }
            }
        }
    }


}  // struct

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

                                Text("Items: \((editablePlaylist ?? currentPlaylist).items.count)")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                            .id(refreshID)  // Refresh when playlist changes
                            .padding()
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))

                            // Add Animation Button
                            HStack {
                                Text("Animations")
                                    .font(.headline)

                                Spacer()

                                Button("Add Animation") {
                                    showingAddAnimation = true
                                }
                                .buttonStyle(.borderedProminent)
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
                                    .buttonStyle(.borderedProminent)
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
                                            currentPlaylist: editablePlaylist ?? currentPlaylist,
                                            onWeightChanged: { newWeight in
                                                editablePlaylist?.items[index].weight = newWeight
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
                                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                            }

                            Spacer(minLength: 50)
                        }
                        .padding()
                    }
                    .navigationTitle("Edit Playlist")
                    .safeAreaInset(edge: .bottom) {
                        HStack {
                            Button("Cancel") {
                                print("DEBUG: Cancel button tapped in EditPlaylistSheet")
                                onCancel()
                            }
                            .buttonStyle(.bordered)

                            Spacer()

                            Button("Save") {
                                print("DEBUG: Save button tapped in EditPlaylistSheet")
                                if let playlist = editablePlaylist {
                                    onSave(playlist)
                                } else {
                                    print("DEBUG: No editablePlaylist to save")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding()
                        .background(.thinMaterial)
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
