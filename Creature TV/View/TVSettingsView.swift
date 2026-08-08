import Common
import SwiftUI

/// The TV's Settings tab: Network configuration plus the local-data reset the other platforms
/// keep in Debug settings. The TV's SwiftData store is a disposable server-backed cache, and a
/// stale schema or bad sync is otherwise undiagnosable from the couch — this is the fix-it
/// button.
struct TVSettingsView: View {

    @State private var showResetConfirm = false
    @State private var isResetting = false
    @State private var resultMessage: String?
    @State private var showResultAlert = false

    var body: some View {
        List {
            Section {
                NavigationLink {
                    NetworkSettingsView()
                } label: {
                    Label("Network", systemImage: "network")
                }
            }

            Section {
                Button(role: .destructive) {
                    showResetConfirm = true
                } label: {
                    if isResetting {
                        Label("Resetting…", systemImage: "arrow.triangle.2.circlepath")
                    } else {
                        Label(
                            "Reset Local Data & Resync",
                            systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(isResetting)
            } footer: {
                Text(
                    "Wipes this Apple TV's local cache (creatures, animations, dialogs, stages, sounds) and pulls everything fresh from the server. Safe: the server is the source of truth."
                )
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog(
            "Reset local data?",
            isPresented: $showResetConfirm,
            titleVisibility: .visible
        ) {
            Button("Reset & Resync", role: .destructive) {
                performReset()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Everything cached on this Apple TV is re-fetched from the server.")
        }
        .alert("Local Data Reset", isPresented: $showResultAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(resultMessage ?? "")
        }
    }

    private func performReset() {
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
