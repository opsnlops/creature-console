import Common
import Foundation
import OSLog
import SwiftData
import SwiftUI

struct PlaylistsTable: View {

    let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "PlaylistsTable")

    @Environment(\.modelContext) private var modelContext

    @Query(sort: \PlaylistModel.name, order: .forward)
    private var playlists: [PlaylistModel]

    // Our Server
    let server = CreatureServerClient.shared

    @State private var errorAlert: ErrorAlert? = nil
    @State private var successBanner: String? = nil

    @State private var selection: PlaylistIdentifier? = nil
    @State private var editingPlaylist: Common.Playlist? = nil
    @State private var showingEditSheet = false
    @State private var showingCreateSheet = false

    @State private var playlistTask: Task<Void, Never>? = nil

    @AppStorage("activeUniverse") var activeUniverse: UniverseIdentifier = 1

    private var playlistTable: some View {
        Table(playlists, selection: $selection) {
            // No tap gestures on cell content — they defeat native single-click row
            // selection on macOS. Double-click/tap is the contextMenu's primaryAction.
            TableColumn("Name") { playlistModel in
                Text(playlistModel.name)
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
        // One unified modifier for both platforms: right-click/long-press menu, plus native
        // row activation (double-click on macOS, tap on iOS) via primaryAction. Single-click
        // on macOS selects natively — no gestures involved.
        .contextMenu(forSelectionType: PlaylistIdentifier.self) {
            (items: Set<PlaylistIdentifier>) in
            if let playlistId = items.first ?? selection,
                let playlistModel = playlists.first(where: { $0.id == playlistId })
            {
                playlistContextMenu(for: playlistModel.toDTO())
            }
        } primaryAction: { items in
            if let playlistId = items.first ?? selection,
                let playlistModel = playlists.first(where: { $0.id == playlistId })
            {
                editPlaylist(playlistModel.toDTO())
            }
        }
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
                        .buttonStyle(.glassProminent)
                    }
                }
            }  // VStack
            .onChange(of: selection) {
                logger.debug("selection is now \(String(describing: selection))")
            }
            .errorAlert($errorAlert, dismissLabel: "Shit")
            .statusBanner($successBanner)
            .toolbar(id: "playlistList") {
                #if os(iOS)
                    ToolbarItem(id: "create", placement: .topBarTrailing) {
                        Button(action: {
                            showingCreateSheet = true
                        }) {
                            Image(systemName: "plus")
                        }
                        .help("Create a new playlist")
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
                        .help("Edit the selected playlist")
                    }

                    ToolbarItem(id: "stop", placement: .topBarTrailing) {
                        Button(action: {
                            stopPlayback()
                        }) {
                            Image(systemName: "stop.circle")
                                .symbolRenderingMode(.palette)
                        }
                        .help("Stop playlist playback")
                    }

                #else
                    ToolbarItem(id: "create", placement: .primaryAction) {
                        Button(action: {
                            showingCreateSheet = true
                        }) {
                            Image(systemName: "plus")
                        }
                        .help("Create a new playlist")
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
                        .help("Edit the selected playlist")
                    }

                    ToolbarItem(id: "stop", placement: .secondaryAction) {
                        Button(action: {
                            stopPlayback()
                        }) {
                            Image(systemName: "stop.circle")
                                .symbolRenderingMode(.palette)
                        }
                        .help("Stop playlist playback")
                    }
                #endif
            }
            .navigationTitle("Playlists")
            .bottomToolbarInset()
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
            switch result {
            case .success(let message):
                logger.debug("Playlist updated successfully: \(message)")
                refreshPlaylistCache()
                // Clean up and close dialog
                showingEditSheet = false
                editingPlaylist = nil
            case .failure(let error):
                let detailedError = ServerError.detailedMessage(from: error)
                logger.error("Save failed with error: \(error)")
                logger.error("Error type: \(type(of: error))")
                errorAlert = ErrorAlert(message: "Failed to save playlist: \(detailedError)")
                logger.error("Failed to save playlist: \(detailedError)")
                logger.error(
                    "Playlist data: \(playlist.name) with \(playlist.items.count) items")
            }
        }
    }

    func createPlaylist(_ playlist: Common.Playlist) {
        Task {
            let result = await server.createPlaylist(playlist)
            switch result {
            case .success:
                logger.debug("Playlist created successfully")
                refreshPlaylistCache()
                showingCreateSheet = false
            case .failure(let error):
                let detailedError = ServerError.detailedMessage(from: error)
                errorAlert = ErrorAlert(message: "Failed to create playlist: \(detailedError)")
                logger.error("Failed to create playlist: \(detailedError)")
            }
        }
    }

    /// Pull the authoritative playlist list from the server and upsert it into the local cache.
    /// Shared by save and create so the two paths can't drift apart.
    private func refreshPlaylistCache() {
        Task {
            let importer = PlaylistImporter(modelContainer: modelContext.container)
            let result = await server.getAllPlaylists()
            switch result {
            case .success(let list):
                do {
                    try await importer.upsertBatch(list)
                    logger.debug("Cache refresh successful")
                } catch {
                    logger.warning("Cache refresh failed: \(error.localizedDescription)")
                }
            case .failure(let error):
                logger.warning("Failed to fetch playlists: \(error.localizedDescription)")
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
                successBanner = message
                logger.debug("Successfully started playlist: \(message)")
            case .failure(let error):
                let detailedError = ServerError.detailedMessage(from: error)
                logger.warning("Unable to start a playlist: \(detailedError)")
                errorAlert = ErrorAlert(message: "Error starting playlist: \(detailedError)")
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
                successBanner = message
                logger.debug("Successfully stopped playlist playback: \(message)")
            case .failure(let error):
                let detailedError = ServerError.detailedMessage(from: error)
                logger.warning("Unable to stop playlist playback: \(detailedError)")
                errorAlert = ErrorAlert(message: "Error stopping playlist: \(detailedError)")
            }
        }
    }


}  // struct
