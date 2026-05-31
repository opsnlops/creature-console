import Common
import Foundation
import OSLog
import SwiftData
import SwiftUI

#if os(iOS)
    import UIKit
#endif

/// Identifies which storyboard to perform. Carries only the (stable) id — the DTO is looked up
/// fresh at presentation, never captured.
private struct PerformRequest: Identifiable {
    let id: StoryboardIdentifier
}

/// Lists the saved storyboards (newest-edited first), mirroring `DialogScriptTable`. Backed by
/// SwiftData (`StoryboardModel`), kept in sync via the `storyboard-list` cache-invalidation path.
struct StoryboardTable: View {

    let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "StoryboardTable")

    @Environment(\.modelContext) private var modelContext

    @Query(sort: \StoryboardModel.updatedAtMillis, order: .reverse)
    private var storyboards: [StoryboardModel]

    let server = CreatureServerClient.shared

    @State private var selection: StoryboardIdentifier? = nil
    /// We track only the *id* to perform — never a captured `Storyboard` value. The DTO is resolved
    /// fresh from the live `@Query` at presentation time, so an edit made just before performing is
    /// always reflected. (Capturing the value inside the context-menu closure snapshots stale data.)
    @State private var performRequest: PerformRequest? = nil
    @State private var showErrorAlert = false
    @State private var alertMessage = ""
    @State private var showSuccessAlert = false
    @State private var successMessage = ""
    @State private var boardToDelete: StoryboardModel? = nil
    @State private var showDeleteConfirm = false

    private var storyboardTable: some View {
        Table(storyboards, selection: $selection) {
            TableColumn("Title") { board in
                Text(board.title.isEmpty ? "Untitled" : board.title)
            }
            .width(min: 220, ideal: 340)

            TableColumn("Tiles") { board in
                Text("\(board.tileCount)")
            }
            .width(min: 60, ideal: 80)

            TableColumn("Last Updated") { board in
                if let date = board.updatedAtDate {
                    Text(date, format: .dateTime.year().month().day().hour().minute())
                        .foregroundStyle(.secondary)
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
            .width(min: 160, ideal: 200)
        }
        #if os(macOS)
            .contextMenu(forSelectionType: StoryboardIdentifier.self) {
                (items: Set<StoryboardIdentifier>) in
                if let id = items.first ?? selection,
                    let board = storyboards.first(where: { $0.id == id })
                {
                    storyboardContextMenu(for: board)
                }
            }
        #else
            .contextMenu {
                if let id = selection, let board = storyboards.first(where: { $0.id == id }) {
                    storyboardContextMenu(for: board)
                }
            }
        #endif
    }

    @ViewBuilder
    private func storyboardContextMenu(for board: StoryboardModel) -> some View {
        Button {
            performRequest = PerformRequest(id: board.id)
        } label: {
            Label("Perform", systemImage: "play.square.stack")
        }

        NavigationLink {
            StoryboardEditor(existing: board.toDTO())
        } label: {
            Label("Edit", systemImage: "pencil")
        }

        Button {
            #if os(macOS)
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(board.id.uuidString.lowercased(), forType: .string)
            #else
                UIPasteboard.general.string = board.id.uuidString.lowercased()
            #endif
        } label: {
            Label("Copy Storyboard ID", systemImage: "doc.on.clipboard")
        }

        Divider()

        Button(role: .destructive) {
            boardToDelete = board
            showDeleteConfirm = true
        } label: {
            Label("Delete Storyboard", systemImage: "trash")
        }
    }

    var body: some View {
        NavigationStack {
            VStack {
                if !storyboards.isEmpty {
                    storyboardTable
                } else {
                    ContentUnavailableView {
                        Label("No Storyboards", systemImage: "square.grid.2x2")
                    } description: {
                        Text(
                            "Create a storyboard — a card of programmable buttons you can tap discreetly during a show to make your characters come alive."
                        )
                    } actions: {
                        NavigationLink {
                            StoryboardEditor(createNew: true)
                        } label: {
                            Label("New Storyboard", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle("Storyboards")
            #if os(macOS)
                .navigationSubtitle("Number of Storyboards: \(storyboards.count)")
            #endif
            .navigationDestination(for: StoryboardIdentifier.self) { id in
                if let board = storyboards.first(where: { $0.id == id }) {
                    StoryboardEditor(existing: board.toDTO())
                } else {
                    Text("Storyboard not found")
                }
            }
            // Full-screen on iOS; macOS has no fullScreenCover, so present a large sheet.
            // The DTO is resolved here, in the parent body, from the live `@Query` — so it's the
            // freshest copy. We also forward `modelContext` into the presentation, because on iOS a
            // cover/sheet doesn't inherit it, which would otherwise leave the perform view's own
            // `@Query` empty.
            #if os(iOS)
                .fullScreenCover(item: $performRequest) { request in
                    performDestination(for: request)
                }
            #else
                .sheet(item: $performRequest) { request in
                    performDestination(for: request)
                    .frame(minWidth: 800, minHeight: 600)
                }
            #endif
            .toolbar(id: "storyboardList") {
                #if os(iOS)
                    ToolbarItem(id: "create", placement: .topBarTrailing) {
                        NavigationLink {
                            StoryboardEditor(createNew: true)
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                #else
                    ToolbarItem(id: "create", placement: .primaryAction) {
                        NavigationLink {
                            StoryboardEditor(createNew: true)
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                    ToolbarItem(id: "edit", placement: .secondaryAction) {
                        if let id = selection, let board = storyboards.first(where: { $0.id == id })
                        {
                            NavigationLink {
                                StoryboardEditor(existing: board.toDTO())
                            } label: {
                                Image(systemName: "pencil")
                            }
                        } else {
                            Button(action: {}) { Image(systemName: "pencil") }.disabled(true)
                        }
                    }
                #endif
            }
            .alert("Error", isPresented: $showErrorAlert) {
                Button("OK") {}
            } message: {
                Text(alertMessage)
            }
            .alert("Success", isPresented: $showSuccessAlert) {
                Button("OK") {}
            } message: {
                Text(successMessage)
            }
            .confirmationDialog(
                "Delete storyboard '\(boardToDelete?.title ?? "")'?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let toDelete = boardToDelete { performDelete(toDelete) }
                }
                Button("Cancel", role: .cancel) { boardToDelete = nil }
            } message: {
                Text("This permanently removes the storyboard from the server.")
            }
        }
    }

    /// Builds the perform view for a request, resolving the freshest DTO from the live `@Query` (the
    /// single source of truth) and forwarding the model container so the perform view's own `@Query`
    /// (fixtures) stays populated — a cover/sheet doesn't inherit it on iOS.
    @ViewBuilder
    private func performDestination(for request: PerformRequest) -> some View {
        if let model = storyboards.first(where: { $0.id == request.id }) {
            StoryboardPerformView(storyboard: model.toDTO())
                .modelContainer(modelContext.container)
        } else {
            ContentUnavailableView(
                "Storyboard Not Found", systemImage: "square.grid.2x2",
                description: Text("It may have been deleted."))
        }
    }

    private func performDelete(_ board: StoryboardModel) {
        let id = board.id
        let title = board.title
        logger.debug("deleting storyboard \(title) (\(id))")
        Task {
            let result = await server.deleteStoryboard(id: id)
            await MainActor.run {
                switch result {
                case .success(let message):
                    successMessage = message
                    showSuccessAlert = true
                    boardToDelete = nil
                    CacheInvalidationProcessor.rebuildStoryboardCache(deleteStaleEntries: true)
                case .failure(let error):
                    alertMessage =
                        "Failed to delete '\(title)': \(ServerError.detailedMessage(from: error))"
                    showErrorAlert = true
                    boardToDelete = nil
                }
            }
        }
    }
}
