import Common
import OSLog
import SwiftData
import SwiftUI

/// The music library: every saved piece, newest first. Opening one lands in the piece editor;
/// pieces are refined there and every refinement becomes a version.
struct MusicLibraryView: View {
    private let logger = Logger(
        subsystem: "io.opsnlops.CreatureConsole", category: "MusicLibraryView")
    private let server = CreatureServerClient.shared

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MusicPieceModel.updatedAtMillis, order: .reverse)
    private var pieces: [MusicPieceModel]

    @State private var pieceToDelete: MusicPieceModel?
    @State private var showDeleteConfirm = false
    @State private var errorAlert: ErrorAlert?
    @State private var successBanner: String?

    var body: some View {
        NavigationStack {
            Group {
                if pieces.isEmpty {
                    ContentUnavailableView {
                        Label("No Pieces Yet", systemImage: "music.note.list")
                    } description: {
                        Text(
                            "Compose a piece here, refine it until it's right, and pick it when a dialog needs music."
                        )
                    } actions: {
                        NavigationLink {
                            MusicLibraryPieceView(pieceId: nil)
                        } label: {
                            Label("New Piece", systemImage: "plus")
                        }
                        .buttonStyle(.glassProminent)
                    }
                } else {
                    List(pieces) { piece in
                        // Destination-style links: a value link needs a navigationDestination
                        // the link can see, and one declared inside this conditional branch is
                        // invisible on iOS ("no matching navigationDestination declaration").
                        NavigationLink {
                            MusicLibraryPieceView(pieceId: piece.id)
                        } label: {
                            row(for: piece)
                        }
                        .contextMenu {
                            Button {
                                Pasteboard.copy(piece.id.uuidString.lowercased())
                            } label: {
                                Label("Copy Piece ID", systemImage: "doc.on.clipboard")
                            }
                            Divider()
                            Button(role: .destructive) {
                                pieceToDelete = piece
                                showDeleteConfirm = true
                            } label: {
                                Label("Delete Piece", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Music Library")
            #if os(macOS)
                .navigationSubtitle("\(pieces.count) piece(s)")
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink {
                        MusicLibraryPieceView(pieceId: nil)
                    } label: {
                        Label("New Piece", systemImage: "plus")
                    }
                }
            }
            .errorAlert($errorAlert)
            .statusBanner($successBanner)
            .confirmationDialog(
                "Delete “\(pieceToDelete?.title ?? "")”?", isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let pieceToDelete { performDelete(pieceToDelete) }
                }
                Button("Cancel", role: .cancel) { pieceToDelete = nil }
            } message: {
                Text(
                    "The piece and its versions leave the library. The sound files stay on the server, and dialogs that already use its music are not affected."
                )
            }
        }
    }

    @ViewBuilder
    private func row(for piece: MusicPieceModel) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "music.quarternote.3")
                .foregroundStyle(Color.accentColor)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(piece.title.isEmpty ? "Untitled" : piece.title)
                Text(
                    "\(TimeHelper.formatDuration(Double(piece.currentDurationMillis) / 1_000)) • \(piece.versionCount) version(s)"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if let date = piece.updatedAtDate {
                Text(date, format: .dateTime.month().day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    private func performDelete(_ piece: MusicPieceModel) {
        let id = piece.id
        let title = piece.title
        Task {
            let result = await server.deleteMusicPiece(id: id)
            await MainActor.run {
                switch result {
                case .success(let message):
                    successBanner = message
                    pieceToDelete = nil
                    // Remove the row now; the invalidation reconciles the rest.
                    modelContext.delete(piece)
                    do {
                        try modelContext.save()
                    } catch {
                        logger.error(
                            "failed to persist deleted music piece locally: \(error.localizedDescription)"
                        )
                    }
                case .failure(let error):
                    errorAlert = ErrorAlert(
                        message:
                            "Failed to delete “\(title)”: \(ServerError.detailedMessage(from: error))"
                    )
                    pieceToDelete = nil
                }
            }
        }
    }
}
