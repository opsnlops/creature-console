import Common
import OSLog
import SwiftUI

/// Lists the stages saved on the server, newest-edited first.
///
/// Mirrors `StoryboardTable`, including how rows activate: a `NavigationLink` inside a `TableColumn`
/// looks right and never fires, so row activation goes through `contextMenu(forSelectionType:)`'s
/// `primaryAction` instead.
///
/// Unlike storyboards and dialog scripts there's no SwiftData mirror behind this — stages are few
/// (one per physical arrangement) and are only read while authoring, so a local cache plus an
/// importer to keep it in sync would be cost without benefit. The trade is that the list has to be
/// re-fetched when returning from the editor rather than tracking a live `@Query`.
struct StageTable: View {

    private let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "StageTable")

    @State private var store = StageStore()
    @State private var selection: StageIdentifier?
    @State private var stageToEdit: Stage?
    @State private var stageToDelete: Stage?
    @State private var showDeleteConfirm = false

    private var stageTable: some View {
        Table(store.stages, selection: $selection) {
            TableColumn("Title") { stage in
                Text(stage.title.isEmpty ? "Untitled" : stage.title)
            }
            .width(min: 200, ideal: 320)

            TableColumn("Creatures") { stage in
                Text("\(stage.placements.count)")
                    .monospacedDigit()
            }
            .width(min: 70, ideal: 90)

            TableColumn("Last Updated") { stage in
                if let date = stage.updatedAtDate {
                    Text(date, format: .dateTime.year().month().day().hour().minute())
                        .foregroundStyle(.secondary)
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
            .width(min: 160, ideal: 200)
        }
        // One unified modifier for both platforms: right-click/long-press menu, plus native row
        // activation (double-click on macOS, tap on iOS) via primaryAction. Editing is the primary
        // action — it's the only thing you can do to a stage that isn't destructive.
        .contextMenu(forSelectionType: StageIdentifier.self) { (items: Set<StageIdentifier>) in
            if let id = items.first ?? selection,
                let stage = store.stages.first(where: { $0.id == id })
            {
                stageContextMenu(for: stage)
            }
        } primaryAction: { items in
            if let id = items.first ?? selection {
                stageToEdit = store.stages.first(where: { $0.id == id })
            }
        }
    }

    @ViewBuilder
    private func stageContextMenu(for stage: Stage) -> some View {
        NavigationLink {
            StageEditor(stageID: stage.id)
        } label: {
            Label("Edit", systemImage: "pencil")
        }

        Button {
            Pasteboard.copy(stage.id.uuidString.lowercased())
        } label: {
            Label("Copy Stage ID", systemImage: "doc.on.clipboard")
        }

        Divider()

        Button(role: .destructive) {
            stageToDelete = stage
            showDeleteConfirm = true
        } label: {
            Label("Delete Stage", systemImage: "trash")
        }
    }

    var body: some View {
        NavigationStack {
            VStack {
                switch store.loadState {
                case .idle, .loading:
                    ProgressView("Loading stages…")
                case .failed(let message):
                    ContentUnavailableView {
                        Label("Couldn't Load Stages", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Try Again") { Task { await store.load() } }
                            .buttonStyle(.glassProminent)
                    }
                case .loaded where store.stages.isEmpty:
                    ContentUnavailableView {
                        Label("No Stages", systemImage: "square.on.square.dashed")
                    } description: {
                        Text(
                            "Create a stage — where each creature physically sits and which way it faces. Bind one to a dialog render and the cast turns to look at whoever is speaking."
                        )
                    } actions: {
                        NavigationLink {
                            StageEditor(createNew: true)
                        } label: {
                            Label("New Stage", systemImage: "plus")
                        }
                        .buttonStyle(.glassProminent)
                    }
                case .loaded:
                    stageTable
                }
            }
            .navigationTitle("Stages")
            #if os(macOS)
                .navigationSubtitle("Number of Stages: \(store.stages.count)")
            #endif
            .navigationDestination(item: $stageToEdit) { stage in
                StageEditor(stageID: stage.id)
            }
            .task { await store.load() }
            // No live query behind this list, so re-fetch when the editor is dismissed; otherwise a
            // rename or a moved creature wouldn't show up on the way back.
            .onChange(of: stageToEdit) { _, newValue in
                if newValue == nil {
                    Task { await store.load() }
                }
            }
            .toolbar(id: "stageList") {
                #if os(iOS)
                    ToolbarItem(id: "create", placement: .topBarTrailing) {
                        NavigationLink {
                            StageEditor(createNew: true)
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                #else
                    ToolbarItem(id: "create", placement: .primaryAction) {
                        NavigationLink {
                            StageEditor(createNew: true)
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                    ToolbarItem(id: "edit", placement: .secondaryAction) {
                        if let id = selection,
                            let stage = store.stages.first(where: { $0.id == id })
                        {
                            NavigationLink {
                                StageEditor(stageID: stage.id)
                            } label: {
                                Image(systemName: "pencil")
                            }
                        } else {
                            Button(action: {}) { Image(systemName: "pencil") }.disabled(true)
                        }
                    }
                #endif
                ToolbarItem(id: "refresh", placement: .secondaryAction) {
                    Button {
                        Task { await store.load() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .confirmationDialog(
                "Delete stage '\(stageToDelete?.title ?? "")'?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    guard let id = stageToDelete?.id else { return }
                    stageToDelete = nil
                    Task { await store.delete(id: id) }
                }
                Button("Cancel", role: .cancel) { stageToDelete = nil }
            } message: {
                Text(
                    "This permanently removes the stage from the server. Animations already rendered against it keep working, but it can't be used for new renders."
                )
            }
        }
    }
}
