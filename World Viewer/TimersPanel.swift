import SwiftUI
import WorldCore

/// The World's promises to itself: what it means to do, and when.
struct TimersPanel: View {
    let store: WorldStore
    @Binding var scried: Scried?
    @State private var selection: TimerID?

    var body: some View {
        List(store.timers, id: \.timerID, selection: $selection) { timer in
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: symbol(for: timer.status))
                    .foregroundStyle(color(for: timer.status))
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(timer.purpose.rawValue)
                            .font(.headline)
                        Text(timer.status.rawValue)
                            .font(.caption2)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .glassEffect(
                                .regular.tint(color(for: timer.status).opacity(0.18)), in: .capsule)
                    }
                    Text(
                        "due \(timer.dueAt, format: .dateTime.month().day().hour().minute().second())"
                    )
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    if !timer.subjectIDs.isEmpty {
                        Text(timer.subjectIDs.map(\.rawValue).joined(separator: ", "))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .onChange(of: selection) { _, timerID in
            scried = store.timers.first { $0.timerID == timerID }.map(Scried.timer)
        }
        .overlay {
            if store.timers.isEmpty {
                ContentUnavailableView(
                    "No timers",
                    systemImage: "hourglass",
                    description: Text("The World has made no promises to itself right now.")
                )
            }
        }
        .toolbar {
            ToolbarItem {
                Button("Refresh", systemImage: "arrow.triangle.2.circlepath") {
                    Task { await store.refreshFactsAndTimers() }
                }
            }
        }
    }

    private func symbol(for status: WorldTimerStatus) -> String {
        switch status {
        case .pending: "hourglass"
        case .firing: "bolt.fill"
        case .fired: "checkmark.circle.fill"
        case .canceled: "xmark.circle"
        }
    }

    private func color(for status: WorldTimerStatus) -> Color {
        switch status {
        case .pending: .yellow
        case .firing: .orange
        case .fired: .green
        case .canceled: .gray
        }
    }
}
