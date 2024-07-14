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

    @State var availablePlaylists: [Common.Playlist] = []
    @State private var selection: Common.Playlist.ID? = nil

    @State private var loadDataTask: Task<Void, Never>? = nil
    @State private var playSoundTask: Task<Void, Never>? = nil

    var body: some View {
        NavigationStack {
            VStack {
                if !availablePlaylists.isEmpty {
                    Table(of: Common.Playlist.self, selection: $selection) {
                        TableColumn("Name", value: \.name)
                            .width(min: 300, ideal: 500)

                        TableColumn("Number") { l in
                            Text(l.items.count, format: .number)
                        }
                        .width(min: 120)

                    } rows: {
                        ForEach(availablePlaylists) { playlist in
                            TableRow(playlist)
                                .contextMenu {
                                    Button {
                                       // playSelected()
                                    } label: {
                                        Label("Play Playlist", systemImage: "music.quarternote.3")
                                    }
                                    //.disabled(sound.transcript.isEmpty)

                                }  //context Menu
                        }  // ForEach
                    }  // rows
                }  // if !availablePlaylists.isEmpty

            }  // VStack
            .onAppear {
                logger.debug("onAppear()")
                loadData()
            }
            .onDisappear {
                loadDataTask?.cancel()
            }
            .onChange(of: selection) {
                logger.debug("selection is now \(String(describing: selection))")
            }
            .alert(isPresented: $showErrorAlert) {
                Alert(
                    title: Text("Unable to get the list of playlists"),
                    message: Text(alertMessage),
                    dismissButton: .default(Text("List this!"))
                )
            }
            .navigationTitle("Playlists")
#if os(macOS)
            .navigationSubtitle("Number of Playlists: \(self.availablePlaylists.count)")
#endif
        }  // Navigation Stack
    }  // View


    func loadData() {
        loadDataTask?.cancel()

        loadDataTask = Task {

            // Go fetch all of the playlists
            let result = await server.getAllPlaylists()
            logger.debug("Loaded all playlists")

            switch result {
                case .success(let data):
                    logger.debug("success!")
                    self.availablePlaylists = data
                case .failure(let error):
                    alertMessage = "Error: \(String(describing: error.localizedDescription))"
                    logger.warning(
                        "Unable to load our playlists: \(String(describing: error.localizedDescription))"
                    )
                    showErrorAlert = true
            }
        }
    }


}  // struct

