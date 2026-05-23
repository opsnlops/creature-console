import Common
import Foundation
import OSLog
import SwiftData
import SwiftUI

#if os(iOS)
    import UIKit
#endif

struct FixturesTable: View {

    let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "FixturesTable")

    @Environment(\.modelContext) private var modelContext

    @Query(sort: \DmxFixtureModel.name, order: .forward)
    private var fixtures: [DmxFixtureModel]

    let server = CreatureServerClient.shared

    @State private var selection: DmxFixtureIdentifier? = nil
    @State private var showErrorAlert = false
    @State private var alertMessage = ""
    @State private var showSuccessAlert = false
    @State private var successMessage = ""
    @State private var fixtureToDelete: DmxFixtureModel? = nil
    @State private var showDeleteConfirm = false

    private var fixtureTable: some View {
        Table(fixtures, selection: $selection) {
            TableColumn("Name") { fixture in
                Text(fixture.name)
                    #if os(macOS)
                        .onTapGesture(count: 2) {
                            // Navigation handled via the surrounding NavigationLink in macOS
                            // sidebar flow; double-click here is a no-op for now.
                        }
                    #endif
            }
            .width(min: 200, ideal: 300)

            TableColumn("Type") { fixture in
                Text(fixture.typeDisplay)
            }
            .width(min: 90, ideal: 120)

            TableColumn("Universe") { fixture in
                if let u = fixture.assignedUniverse {
                    Text("\(u)")
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
            .width(min: 80, ideal: 100)

            TableColumn("Offset") { fixture in
                Text("\(fixture.channelOffset)")
            }
            .width(min: 70, ideal: 90)

            TableColumn("Channels") { fixture in
                Text("\(fixture.channelCount)")
            }
            .width(min: 80, ideal: 100)

            TableColumn("Patterns") { fixture in
                Text("\(fixture.patternCount)")
            }
            .width(min: 80, ideal: 100)

            TableColumn("Bindings") { fixture in
                Text("\(fixture.bindingCount)")
            }
            .width(min: 80, ideal: 100)
        }
        #if os(macOS)
            .contextMenu(forSelectionType: DmxFixtureIdentifier.self) {
                (items: Set<DmxFixtureIdentifier>) in
                if let fixtureId = items.first ?? selection,
                    let fixture = fixtures.first(where: { $0.id == fixtureId })
                {
                    fixtureContextMenu(for: fixture)
                }
            }
        #else
            .contextMenu {
                if let fixtureId = selection,
                    let fixture = fixtures.first(where: { $0.id == fixtureId })
                {
                    fixtureContextMenu(for: fixture)
                }
            }
        #endif
    }

    @ViewBuilder
    private func fixtureContextMenu(for fixture: DmxFixtureModel) -> some View {
        NavigationLink {
            FixtureEditor(existing: fixture.toDTO())
        } label: {
            Label("Edit Fixture", systemImage: "pencil")
        }

        Button {
            #if os(macOS)
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(fixture.id, forType: .string)
            #else
                UIPasteboard.general.string = fixture.id
            #endif
        } label: {
            Label("Copy Fixture ID", systemImage: "doc.on.clipboard")
        }

        Divider()

        Button(role: .destructive) {
            fixtureToDelete = fixture
            showDeleteConfirm = true
        } label: {
            Label("Delete Fixture", systemImage: "trash")
        }
    }

    var body: some View {
        NavigationStack {
            VStack {
                if !fixtures.isEmpty {
                    fixtureTable
                } else {
                    ContentUnavailableView {
                        Label("No Fixtures", systemImage: "lightbulb.led")
                    } description: {
                        Text(
                            "Create a DMX fixture to drive lights, smoke machines, foggers, or any other DMX device from animations and bindings."
                        )
                    } actions: {
                        NavigationLink {
                            FixtureEditor(createNew: true)
                        } label: {
                            Label("New Fixture", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle("DMX Fixtures")
            #if os(macOS)
                .navigationSubtitle("Number of Fixtures: \(fixtures.count)")
            #endif
            .navigationDestination(for: DmxFixtureIdentifier.self) { fixtureId in
                if let fixture = fixtures.first(where: { $0.id == fixtureId }) {
                    FixtureEditor(existing: fixture.toDTO())
                } else {
                    Text("Fixture not found")
                }
            }
            .toolbar(id: "fixturesList") {
                #if os(iOS)
                    ToolbarItem(id: "create", placement: .topBarTrailing) {
                        NavigationLink {
                            FixtureEditor(createNew: true)
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                #else
                    ToolbarItem(id: "create", placement: .primaryAction) {
                        NavigationLink {
                            FixtureEditor(createNew: true)
                        } label: {
                            Image(systemName: "plus")
                        }
                    }

                    ToolbarItem(id: "edit", placement: .secondaryAction) {
                        if let selectedId = selection,
                            let fixture = fixtures.first(where: { $0.id == selectedId })
                        {
                            NavigationLink {
                                FixtureEditor(existing: fixture.toDTO())
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
                "Delete fixture '\(fixtureToDelete?.name ?? "")'?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let toDelete = fixtureToDelete {
                        performDelete(toDelete)
                    }
                }
                Button("Cancel", role: .cancel) {
                    fixtureToDelete = nil
                }
            } message: {
                Text(
                    "This permanently removes the fixture from the server. Bindings on other devices won't be affected."
                )
            }
        }
    }

    private func performDelete(_ fixture: DmxFixtureModel) {
        let id = fixture.id
        let name = fixture.name
        logger.debug("deleting fixture \(name) (\(id))")
        Task {
            let result = await server.deleteFixture(id: id)
            await MainActor.run {
                switch result {
                case .success(let message):
                    logger.info("delete succeeded: \(message)")
                    successMessage = message
                    showSuccessAlert = true
                    fixtureToDelete = nil
                    // Cache will be refreshed by the websocket invalidation broadcast;
                    // optimistically trigger a refresh anyway in case that lags.
                    CacheInvalidationProcessor.rebuildFixtureCache(deleteStaleEntries: true)
                case .failure(let error):
                    let detailed = ServerError.detailedMessage(from: error)
                    logger.warning("delete failed: \(detailed)")
                    alertMessage = "Failed to delete fixture '\(name)': \(detailed)"
                    showErrorAlert = true
                    fixtureToDelete = nil
                }
            }
        }
    }
}
