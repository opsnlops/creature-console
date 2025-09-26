import Common
import SwiftUI

#if os(iOS)
    import UIKit
#endif

struct LogView: View {
    @State private var logManagerState = LogManagerState(logMessages: [])
    @State private var isUserScrolling = false
    @State private var autoScrollEnabled = true
    @State private var selectedLogLevel: ServerLogLevel = .debug

    private let dateFormatter: DateFormatter

    init() {
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "YYYY-MM-dd HH:mm:ss"
    }

    // Filter messages based on selected log level
    private var filteredMessages: [LogItem] {
        logManagerState.logMessages.filter { message in
            message.level.rawValue >= selectedLogLevel.rawValue
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Compact log level filter
            HStack {
                Text("Level:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Picker("Log Level", selection: $selectedLogLevel) {
                    ForEach(
                        ServerLogLevel.allCases.filter { $0 != .off && $0 != .unknown }, id: \.self
                    ) {
                        level in
                        Text(level.description.capitalized).tag(level)
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()

                Spacer()

                Text("\(filteredMessages.count)/\(logManagerState.logMessages.count)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
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
                .onChange(of: filteredMessages) { _, newMessages in
                    if autoScrollEnabled, let lastMessage = newMessages.last {
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
                .onAppear {
                    // Scroll to bottom on initial appearance
                    if let lastMessage = filteredMessages.last {
                        scrollView.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
                .task { @MainActor in
                    // Get initial state immediately
                    let currentState = await LogManager.shared.getCurrentState()
                    logManagerState = currentState

                    // Then subscribe to updates with proper cancellation checking
                    for await state in await LogManager.shared.stateUpdates {
                        guard !Task.isCancelled else { break }
                        logManagerState = state
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
        #if os(iOS)
            .toolbar(id: "global-bottom-status") {
                if UIDevice.current.userInterfaceIdiom == .phone {
                    ToolbarItem(id: "status", placement: .bottomBar) {
                        BottomStatusToolbarContent()
                    }
                }
            }
        #endif
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
        default:
            return Color.primary
        }
    }

    private func backgroundColor(_ level: ServerLogLevel) -> Color {
        switch level {
        case .error, .critical:
            return Color.red.opacity(0.1)
        case .warn:
            return Color.yellow.opacity(0.1)
        case .info:
            return Color.blue.opacity(0.1)
        default:
            return Color.gray.opacity(0.1)
        }
    }
}

private struct LogRowView: View {
    let log: LogItem
    let formattedDate: String
    let levelColor: Color
    let backgroundColor: Color

    var body: some View {
        HStack(alignment: .top) {
            Text("[\(formattedDate)]")
                .font(.footnote)
                .foregroundColor(Color.secondary)
            Text("[\(log.level.description)]")
                .font(.footnote)
                .bold()
                .foregroundColor(levelColor)
            Text(log.message)
                .font(.body)
                .padding(.leading, 4)
                .foregroundColor(Color.primary)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundColor)
        .padding(.vertical, 2)
    }
}
