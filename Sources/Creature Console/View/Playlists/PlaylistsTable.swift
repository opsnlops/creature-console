import Common
import Foundation
import OSLog
import SwiftUI

struct PlaylistsTable: View {

    let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "PlaylistsTable")


    // Our Server
    let server = CreatureServerClient.shared

    @State private var showErrorAlert = false
    @State private var alertMessage = ""

    @State private var selection: Common.Playlist.ID? = nil

    @State private var playlistTask: Task<Void, Never>? = nil

    // Update if this changes
    @ObservedObject private var playlistCache = PlaylistCache.shared

    @AppStorage("activeUniverse") var activeUniverse: UniverseIdentifier = 1

    var body: some View {
        NavigationStack {
            VStack {
                if !playlistCache.playlists.isEmpty {
                    Table(of: Common.Playlist.self, selection: $selection) {
                        TableColumn("Name", value: \.name)
                            .width(min: 300, ideal: 500)

                        TableColumn("Number") { l in
                            Text(l.items.count, format: .number)
                        }
                        .width(min: 120)

                    } rows: {
                        ForEach(playlistCache.playlists.values.sorted(by: { $0.name < $1.name })) { playlist in
                            TableRow(playlist)
                                .contextMenu {
                                    Button {
                                       playSelected()
                                    } label: {
                                        Label("Play Playlist", systemImage: "music.quarternote.3")
                                    }


                                }  //context Menu
                        }  // ForEach
                    }  // rows
                }  // if !availablePlaylists.isEmpty

            }  // VStack
            .onChange(of: selection) {
                logger.debug("selection is now \(String(describing: selection))")
            }
            .alert(isPresented: $showErrorAlert) {
                Alert(
                    title: Text("Error"),
                    message: Text(alertMessage),
                    dismissButton: .default(Text("Crap"))
                )
            }
            .toolbar(id: "playlistList") {
                ToolbarItem(id: "stop", placement: .secondaryAction) {
                    Button(action: {
                        stopPlayback()
                    }) {
                        Image(systemName: "stop.circle")
                            .symbolRenderingMode(.palette)
                    }
                }
            }
            .navigationTitle("Playlists")
#if os(macOS)
            .navigationSubtitle("Number of Playlists: \(self.playlistCache.playlists.values.count)")
#endif
        }  // Navigation Stack
    }  // View


    func playSelected() {

        logger.debug("Attempting to play the selected playlist on the active universe")

        playlistTask?.cancel()

        playlistTask = Task {

            // Go see what, if anything, is selected
            if let playlistId = selection {
                let result = await server.startPlayingPlaylist(universe: activeUniverse, playlistId: playlistId)
                switch result {
                case .success(let message):
                    print(message)
                case .failure(let error):
                    DispatchQueue.main.async {
                        alertMessage = "Error: \(String(describing: error.localizedDescription))"
                        logger.warning(
                            "Unable to start a playlist: \(String(describing: error.localizedDescription))"
                        )
                        showErrorAlert = true
                    }

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
                    print(message)
                case .failure(let error):
                    DispatchQueue.main.async {
                        alertMessage = "Error: \(String(describing: error.localizedDescription))"
                        logger.warning(
                            "Unable to stop playlist playback: \(String(describing: error.localizedDescription))"
                        )
                        showErrorAlert = true
                    }

                }
            }
        }




}  // struct

