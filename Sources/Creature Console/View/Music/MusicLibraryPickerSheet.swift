import Common
import SwiftData
import SwiftUI

/// Pick a saved piece to use under a dialog. The chosen piece's current version is what the
/// dialog's music will be composed from.
struct MusicLibraryPickerSheet: View {
    /// Length of the dialog the piece must cover, when known.
    let dialogDurationMilliseconds: Int64?
    let onPick: (SavedMusicPiece, SavedMusicVersion) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \MusicPieceModel.updatedAtMillis, order: .reverse)
    private var pieces: [MusicPieceModel]

    var body: some View {
        NavigationStack {
            Group {
                if pieces.isEmpty {
                    ContentUnavailableView {
                        Label("The Library Is Empty", systemImage: "music.note.list")
                    } description: {
                        Text("Compose a piece in Music → New Piece, then pick it here.")
                    }
                } else {
                    List(pieces) { model in
                        let piece = model.toDTO()
                        if let version = piece.currentVersion, version.canBeReferenced {
                            Button {
                                onPick(piece, version)
                                dismiss()
                            } label: {
                                row(piece: piece, version: version)
                            }
                            .buttonStyle(.plain)
                        } else {
                            row(piece: piece, version: piece.currentVersion)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Use a Piece")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .frame(minWidth: 420, minHeight: 360)
    }

    @ViewBuilder
    private func row(piece: SavedMusicPiece, version: SavedMusicVersion?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "music.quarternote.3").frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(piece.title.isEmpty ? "Untitled" : piece.title)
                Text(detail(piece: piece, version: version))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }

    private func detail(piece: SavedMusicPiece, version: SavedMusicVersion?) -> String {
        guard let version else { return "No versions yet" }
        var parts = [
            TimeHelper.formatDuration(Double(version.durationMilliseconds) / 1_000),
            "\(piece.versions.count) version(s)",
        ]
        if !version.canBeReferenced {
            parts.append("not kept at ElevenLabs — can't be reused")
        } else if let dialogDurationMilliseconds {
            if version.durationMilliseconds >= dialogDurationMilliseconds {
                parts.append("covers the dialog")
            } else {
                parts.append(
                    "shorter than the dialog by \(TimeHelper.formatDuration(Double(dialogDurationMilliseconds - version.durationMilliseconds) / 1_000)); a matching tail will be composed"
                )
            }
        }
        return parts.joined(separator: " • ")
    }
}
