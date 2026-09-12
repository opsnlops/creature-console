import SwiftUI
import WorldCore

/// Who is logged into the world: one mind per character, one region each, kept alive by
/// heartbeats. This is the flock as the world sees it.
struct CharactersPanel: View {
    let store: WorldStore
    @Binding var scried: Scried?
    @State private var selection: CharacterSessionID?

    var body: some View {
        List(store.characters, id: \.sessionID, selection: $selection) { session in
            CharacterRow(session: session)
        }
        .onChange(of: selection) { _, sessionID in
            scried = store.characters.first { $0.sessionID == sessionID }.map(Scried.character)
        }
        .overlay {
            if store.characters.isEmpty {
                ContentUnavailableView(
                    "Nobody is logged in",
                    systemImage: "bird",
                    description: Text(
                        "A character appears here the moment its mind logs into the world.")
                )
            }
        }
        .toolbar {
            ToolbarItem {
                Button("Refresh", systemImage: "arrow.triangle.2.circlepath") {
                    Task { await store.refreshCharacters() }
                }
            }
        }
    }
}

struct CharacterRow: View {
    let session: CharacterSession

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: "bird.fill")
                .foregroundStyle(color)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(session.characterID.rawValue)
                        .font(.headline)
                    Text(session.state.rawValue)
                        .font(.caption2)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .glassEffect(.regular.tint(color.opacity(0.18)), in: .capsule)
                    Text(session.regionID.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(
                    "\(session.instance.host) · pid \(session.instance.processID)"
                        + (session.instance.version.map { " · creature-agent \($0)" } ?? "")
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Text(
                        "in since \(session.loggedInAt, format: .dateTime.hour().minute().second())"
                    )
                    Text(
                        "heartbeat \(session.lastHeartbeatAt, format: .dateTime.hour().minute().second())"
                    )
                    if let ended = session.endedAt {
                        Text("ended \(ended, format: .dateTime.hour().minute().second())")
                    }
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    private var color: Color {
        switch session.state {
        case .active: .green
        case .expired: .orange
        case .loggedOut: .gray
        }
    }
}
