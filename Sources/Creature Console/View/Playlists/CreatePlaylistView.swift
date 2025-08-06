import Common
import SwiftUI

struct CreatePlaylistView: View {
    let onCreate: (Common.Playlist) -> Void

    @State private var playlistName: String = ""
    @State private var showErrorAlert = false
    @State private var alertMessage = ""

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 12) {
                    Text("Create New Playlist")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text(
                        "Enter a name for your playlist. You can add animations after creating it."
                    )
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                }

                // Input Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Playlist Name")
                        .font(.headline)

                    TextField("Enter playlist name", text: $playlistName)
                        .textFieldStyle(.roundedBorder)
                        .font(.body)
                }
                .padding(20)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))

                Spacer()
            }
            .padding(24)
            .frame(maxWidth: 420)
            .navigationTitle("New Playlist")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 12) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button("Create") {
                        createPlaylist()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(playlistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding()
                .background(.thinMaterial)
            }
        }
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK") {}
        } message: {
            Text(alertMessage)
        }
    }

    private func createPlaylist() {
        let trimmedName = playlistName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else {
            alertMessage = "Playlist name cannot be empty"
            showErrorAlert = true
            return
        }

        let newPlaylist = Common.Playlist(
            id: UUID().uuidString,
            name: trimmedName,
            items: []
        )

        onCreate(newPlaylist)
        dismiss()
    }
}

#Preview {
    CreatePlaylistView { _ in }
}
