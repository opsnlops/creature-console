import Common
import SwiftUI

struct CreatePlaylistView: View {
    let onCreate: (Common.Playlist) -> Void

    @State private var playlistName: String = ""
    @State private var errorAlert: ErrorAlert? = nil

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
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))

                Spacer()
            }
            .padding(24)
            .frame(maxWidth: 420)
            .navigationTitle("New Playlist")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .safeAreaInset(edge: .bottom) {
                // Compact floating glass capsule, trailing like a standard sheet's action
                // buttons — not an edge-to-edge bar.
                HStack(spacing: 12) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .buttonStyle(.glass)

                    Button("Create") {
                        createPlaylist()
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(playlistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .glassEffect(.regular.interactive(), in: .capsule)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal)
                .padding(.bottom, 10)
            }
        }
        .errorAlert($errorAlert)
    }

    private func createPlaylist() {
        let trimmedName = playlistName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else {
            errorAlert = ErrorAlert(message: "Playlist name cannot be empty")
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
