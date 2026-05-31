import Common
import Foundation
import OSLog
import SwiftData
import SwiftUI

#if os(iOS)
    import UIKit
#endif

/// Lists the saved dialog scripts (newest-edited first), mirroring `FixturesTable`. Backed by
/// SwiftData (`DialogScriptModel`), which is kept in sync from the server via the
/// `dialog-script-list` cache invalidation path.
struct DialogScriptTable: View {

    let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "DialogScriptTable")

    @Environment(\.modelContext) private var modelContext

    @Query(sort: \DialogScriptModel.updatedAtMillis, order: .reverse)
    private var scripts: [DialogScriptModel]

    let server = CreatureServerClient.shared

    @State private var selection: DialogScriptIdentifier? = nil
    @State private var showErrorAlert = false
    @State private var alertMessage = ""
    @State private var showSuccessAlert = false
    @State private var successMessage = ""
    @State private var scriptToDelete: DialogScriptModel? = nil
    @State private var showDeleteConfirm = false

    private var scriptTable: some View {
        Table(scripts, selection: $selection) {
            TableColumn("Title") { script in
                Text(script.title.isEmpty ? "Untitled" : script.title)
            }
            .width(min: 220, ideal: 340)

            TableColumn("Turns") { script in
                Text("\(script.turnCount)")
            }
            .width(min: 60, ideal: 80)

            TableColumn("Last Updated") { script in
                if let date = script.updatedAtDate {
                    Text(date, format: .dateTime.year().month().day().hour().minute())
                        .foregroundStyle(.secondary)
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
            .width(min: 160, ideal: 200)
        }
        #if os(macOS)
            .contextMenu(forSelectionType: DialogScriptIdentifier.self) {
                (items: Set<DialogScriptIdentifier>) in
                if let scriptId = items.first ?? selection,
                    let script = scripts.first(where: { $0.id == scriptId })
                {
                    scriptContextMenu(for: script)
                }
            }
        #else
            .contextMenu {
                if let scriptId = selection,
                    let script = scripts.first(where: { $0.id == scriptId })
                {
                    scriptContextMenu(for: script)
                }
            }
        #endif
    }

    @ViewBuilder
    private func scriptContextMenu(for script: DialogScriptModel) -> some View {
        NavigationLink {
            DialogScriptEditor(existing: script.toDTO())
        } label: {
            Label("Edit Dialog", systemImage: "pencil")
        }

        Button {
            #if os(macOS)
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(script.id.uuidString.lowercased(), forType: .string)
            #else
                UIPasteboard.general.string = script.id.uuidString.lowercased()
            #endif
        } label: {
            Label("Copy Script ID", systemImage: "doc.on.clipboard")
        }

        Divider()

        Button(role: .destructive) {
            scriptToDelete = script
            showDeleteConfirm = true
        } label: {
            Label("Delete Dialog", systemImage: "trash")
        }
    }

    var body: some View {
        NavigationStack {
            VStack {
                if !scripts.isEmpty {
                    scriptTable
                } else {
                    ContentUnavailableView {
                        Label("No Dialogs", systemImage: "text.bubble")
                    } description: {
                        Text(
                            "Create a dialog script to author a multi-character scene — each creature speaks in turn, and the server renders it into a single, jointly-voiced multi-track animation."
                        )
                    } actions: {
                        NavigationLink {
                            DialogScriptEditor(createNew: true)
                        } label: {
                            Label("New Dialog", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle("Dialogs")
            #if os(macOS)
                .navigationSubtitle("Number of Dialogs: \(scripts.count)")
            #endif
            .navigationDestination(for: DialogScriptIdentifier.self) { scriptId in
                if let script = scripts.first(where: { $0.id == scriptId }) {
                    DialogScriptEditor(existing: script.toDTO())
                } else {
                    Text("Dialog script not found")
                }
            }
            .toolbar(id: "dialogList") {
                #if os(iOS)
                    ToolbarItem(id: "create", placement: .topBarTrailing) {
                        NavigationLink {
                            DialogScriptEditor(createNew: true)
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                #else
                    ToolbarItem(id: "create", placement: .primaryAction) {
                        NavigationLink {
                            DialogScriptEditor(createNew: true)
                        } label: {
                            Image(systemName: "plus")
                        }
                    }

                    ToolbarItem(id: "edit", placement: .secondaryAction) {
                        if let selectedId = selection,
                            let script = scripts.first(where: { $0.id == selectedId })
                        {
                            NavigationLink {
                                DialogScriptEditor(existing: script.toDTO())
                            } label: {
                                Image(systemName: "pencil")
                            }
                        } else {
                            Button(action: {}) {
                                Image(systemName: "pencil")
                            }
                            .disabled(true)
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
                "Delete dialog '\(scriptToDelete?.title ?? "")'?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let toDelete = scriptToDelete {
                        performDelete(toDelete)
                    }
                }
                Button("Cancel", role: .cancel) {
                    scriptToDelete = nil
                }
            } message: {
                Text(
                    "This permanently removes the script from the server. Animations already rendered from it keep their own copy of the turns and are not affected."
                )
            }
        }
    }

    private func performDelete(_ script: DialogScriptModel) {
        let id = script.id
        let title = script.title
        logger.debug("deleting dialog script \(title) (\(id))")
        Task {
            let result = await server.deleteDialogScript(id: id)
            await MainActor.run {
                switch result {
                case .success(let message):
                    logger.info("delete succeeded: \(message)")
                    successMessage = message
                    showSuccessAlert = true
                    scriptToDelete = nil
                    // The websocket invalidation will refresh the cache shortly; trigger an
                    // optimistic refresh too in case that lags.
                    CacheInvalidationProcessor.rebuildDialogScriptCache(deleteStaleEntries: true)
                case .failure(let error):
                    let detailed = ServerError.detailedMessage(from: error)
                    logger.warning("delete failed: \(detailed)")
                    alertMessage = "Failed to delete dialog '\(title)': \(detailed)"
                    showErrorAlert = true
                    scriptToDelete = nil
                }
            }
        }
    }
}
