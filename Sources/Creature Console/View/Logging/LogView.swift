import Common
import SwiftUI

struct LogView: View {
    @ObservedObject var logManager = LogManager.shared
    @State private var isUserScrolling = false
    @State private var autoScrollEnabled = true

    private let dateFormatter: DateFormatter

    init() {
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "YYYY-MM-dd HH:mm:ss"
    }

    var body: some View {
        ScrollViewReader { scrollView in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(logManager.logMessages) { log in
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
                        if let lastId = logManager.logMessages.last?.id {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                scrollView.scrollTo(lastId, anchor: .bottom)
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .padding()
                }
            }
            .onChange(of: logManager.logMessages) { _, newMessages in
                if autoScrollEnabled, let lastMessage = newMessages.last {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        scrollView.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
            .onAppear {
                // Scroll to bottom on initial appearance
                if let lastMessage = logManager.logMessages.last {
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
