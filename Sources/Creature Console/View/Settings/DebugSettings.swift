import Common
import Foundation
import SwiftUI

/// Debug tools for the local SwiftData cache. This brings the macOS "Caches" menu (and a
/// full store reset) to every platform — on iOS it's the only way to recover when items
/// deleted on the server are still showing up locally.
struct DebugSettingsView: View {

    @State private var isResetting = false
    @State private var showResetConfirmation = false
    @State private var resultMessage = ""
    @State private var showResultAlert = false

    private let cacheActions: [(title: String, icon: String, action: () -> Void)] = [
        (
            "Creatures", "bird",
            { CacheInvalidationProcessor.rebuild(.creature, deleteStaleEntries: true) }
        ),
        (
            "Animations", "figure.dance",
            { CacheInvalidationProcessor.rebuild(.animation, deleteStaleEntries: true) }
        ),
        (
            "Playlists", "list.bullet",
            { CacheInvalidationProcessor.rebuild(.playlist, deleteStaleEntries: true) }
        ),
        (
            "Sound List", "speaker.wave.2",
            { CacheInvalidationProcessor.rebuild(.soundList, deleteStaleEntries: true) }
        ),
        (
            "Fixtures", "lightbulb",
            { CacheInvalidationProcessor.rebuild(.fixture, deleteStaleEntries: true) }
        ),
        (
            "Dialog Scripts", "text.bubble",
            { CacheInvalidationProcessor.rebuild(.dialogScript, deleteStaleEntries: true) }
        ),
        (
            "Storyboards", "rectangle.grid.2x2",
            { CacheInvalidationProcessor.rebuild(.storyboard, deleteStaleEntries: true) }
        ),
    ]

    var body: some View {
        ZStack {

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: "ladybug")
                            .font(.system(size: 16, weight: .semibold))
                            .padding(8)
                            .glassEffect(
                                .regular.tint(.accentColor).interactive(),
                                in: .rect(cornerRadius: 8))
                        Text("Debug")
                            .font(.largeTitle.bold())
                    }
                    .padding(.bottom, 8)

                    GlassEffectContainer(spacing: 24) {
                        // Card: Local Data reset
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Local Data", systemImage: "externaldrive.badge.xmark")
                                .font(.headline)
                            Text(
                                "Wipes every locally cached record (creatures, animations, playlists, sounds, fixtures, dialog scripts, storyboards, and server logs) and pulls a fresh copy from the server. Use this when items deleted on the server are still showing up here."
                            )
                            .font(.callout)
                            .foregroundStyle(.secondary)

                            HStack {
                                Spacer()
                                if isResetting {
                                    ProgressView()
                                        .controlSize(.small)
                                        .padding(.trailing, 8)
                                }
                                Button(role: .destructive) {
                                    showResetConfirmation = true
                                } label: {
                                    Label(
                                        isResetting ? "Re-syncing…" : "Reset Local Data & Re-sync",
                                        systemImage: "arrow.trianglehead.2.clockwise"
                                    )
                                }
                                .buttonStyle(.glassProminent)
                                .tint(.red)
                                .disabled(isResetting)
                            }
                        }
                        .padding(12)
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))

                        // Card: per-cache invalidation (mirrors the macOS "Caches" menu)
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Caches", systemImage: "internaldrive")
                                .font(.headline)
                            Text("Re-fetch a single cache from the server, removing stale entries.")
                                .font(.callout)
                                .foregroundStyle(.secondary)

                            LazyVGrid(
                                columns: [
                                    GridItem(
                                        .adaptive(minimum: 160), spacing: 12, alignment: .leading)
                                ],
                                alignment: .leading, spacing: 12
                            ) {
                                ForEach(cacheActions, id: \.title) { cache in
                                    Button(action: cache.action) {
                                        Label(cache.title, systemImage: cache.icon)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .buttonStyle(.glass)
                                }
                            }

                            HStack {
                                Spacer()
                                Button {
                                    CacheInvalidationProcessor.rebuildAllCaches()
                                } label: {
                                    Label(
                                        "Rebuild All Caches",
                                        systemImage: "arrow.trianglehead.2.clockwise")
                                }
                                .buttonStyle(.glassProminent)
                            }
                        }
                        .padding(12)
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
                    }

                    Spacer(minLength: 0)
                }
                .padding(24)
            }
        }
        .confirmationDialog(
            "Reset all local data?",
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset & Re-sync", role: .destructive) {
                resetLocalData()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This wipes the local SwiftData store and re-downloads everything from the server. The server itself is not touched."
            )
        }
        .alert("Local Data Reset", isPresented: $showResultAlert) {
            Button("OK") {}
        } message: {
            Text(resultMessage)
        }
    }

    private func resetLocalData() {
        isResetting = true
        Task {
            do {
                try await CacheInvalidationProcessor.resetLocalStoreAndResync()
                resultMessage = "Local store wiped and fresh data synced from the server."
            } catch {
                resultMessage = "Reset failed: \(ServerError.detailedMessage(from: error))"
            }
            isResetting = false
            showResultAlert = true
        }
    }
}

#Preview {
    DebugSettingsView()
}
