import Common
import SwiftData
import SwiftUI

#if os(iOS)
    import UIKit
#endif

struct LogView: View {
    @Environment(\.modelContext) private var modelContext

    @AppStorage("serverLogsScrollBackLines") private var serverLogsScrollBackLines: Int = 150

    // Fetch logs in reverse order (newest first)
    @Query(
        sort: \ServerLogModel.timestamp,
        order: .reverse
    )
    private var serverLogsReversed: [ServerLogModel]

    @State private var autoScrollEnabled = true
    @State private var selectedLogLevel: ServerLogLevel = .debug
    @State private var searchText = ""

    private let dateFormatter: DateFormatter

    init() {
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "YYYY-MM-dd HH:mm:ss"
    }

    // Reverse back to chronological order and take only the configured number of recent logs
    private var serverLogs: [ServerLogModel] {
        let limit = max(10, min(500, serverLogsScrollBackLines))
        return Array(serverLogsReversed.prefix(limit).reversed())
    }

    // Convert ServerLogModel to LogItem for display
    private var logItems: [LogItem] {
        serverLogs.map { $0.toLogItem() }
    }

    // Filter messages based on selected log level and search text
    private var filteredMessages: [LogItem] {
        logItems.filter { message in
            let matchesLevel = message.level.rawValue >= selectedLogLevel.rawValue
            let matchesSearch =
                searchText.isEmpty
                || message.message.localizedCaseInsensitiveContains(searchText)
                || message.logger_name.localizedCaseInsensitiveContains(searchText)
            return matchesLevel && matchesSearch
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search and filter toolbar
            HStack(spacing: 8) {
                TextField("Search logs...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 300)

                if !searchText.isEmpty {
                    Button("Clear") { searchText = "" }
                        .buttonStyle(.borderless)
                }

                Spacer()

                Text("Level:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Level", selection: $selectedLogLevel) {
                    ForEach(
                        ServerLogLevel.allCases.filter { $0 != .off && $0 != .unknown }, id: \.self
                    ) {
                        level in
                        Text(level.description.capitalized).tag(level)
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()

                Text("\(filteredMessages.count)/\(serverLogs.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal)
            .padding(.vertical, 6)

            ScrollViewReader { scrollView in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(filteredMessages) { log in
                            LogRowView(
                                log: log,
                                formattedDate: formattedDate(log.timestamp),
                                levelColor: levelColor(log.level),
                                backgroundColor: backgroundColor(log.level)
                            )
                            .id(log.id)
                        }
                    }
                    .onTapGesture {
                        // Allow user to disable auto-scroll by tapping
                        autoScrollEnabled.toggle()
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if !autoScrollEnabled {
                        Button("Auto-scroll") {
                            autoScrollEnabled = true
                            if let lastId = filteredMessages.last?.id {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    scrollView.scrollTo(lastId, anchor: .bottom)
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .padding()
                    }
                }
                .onChange(of: serverLogsReversed.count) { _, _ in
                    // When new logs arrive, scroll to bottom if auto-scroll is enabled
                    if autoScrollEnabled, let lastMessage = filteredMessages.last {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            scrollView.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: selectedLogLevel) { _, _ in
                    // When filter changes, scroll to bottom if auto-scroll is enabled
                    if autoScrollEnabled, let lastMessage = filteredMessages.last {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            scrollView.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: searchText) { _, _ in
                    // When search changes, scroll to bottom if auto-scroll is enabled
                    if autoScrollEnabled, let lastMessage = filteredMessages.last {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            scrollView.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
                .onAppear {
                    // Scroll to bottom on initial appearance
                    if let lastMessage = filteredMessages.last {
                        scrollView.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
            .frame(minWidth: 500, minHeight: 300)
            .padding()
            #if os(iOS)
                .background(Color(UIColor.systemBackground))
            #endif
            #if os(macOS)
                .background(Color(NSColor.windowBackgroundColor))
            #endif
        }
    }

    private func formattedDate(_ date: Date) -> String {
        return dateFormatter.string(from: date)
    }

    private func levelColor(_ level: ServerLogLevel) -> Color {
        switch level {
        case .error:
            return Color.red
        case .critical:
            return Color.orange
        case .warn:
            return Color.yellow
        case .info:
            return Color.blue
        case .debug:
            return Color.cyan
        case .trace:
            return Color.purple
        default:
            return Color.secondary
        }
    }

    private func backgroundColor(_ level: ServerLogLevel) -> Color {
        switch level {
        case .error, .critical:
            return Color.red.opacity(0.08)
        case .warn:
            return Color.yellow.opacity(0.08)
        case .info:
            return Color.blue.opacity(0.05)
        case .debug:
            return Color.cyan.opacity(0.05)
        case .trace:
            return Color.purple.opacity(0.05)
        default:
            return Color.clear
        }
    }
}

private struct LogRowView: View {
    let log: LogItem
    let formattedDate: String
    let levelColor: Color
    let backgroundColor: Color

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("[\(formattedDate)]")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Text(log.level.description.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(levelColor)
                .frame(width: 50, alignment: .leading)

            Text(log.message)
                .font(.body)
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundColor)
    }
}
