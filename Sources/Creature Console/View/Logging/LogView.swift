import Common
import SwiftUI

struct LogView: View {
    @ObservedObject var logManager = LogManager.shared

    private let dateFormatter: DateFormatter

    init() {
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "YYYY-MM-dd HH:mm:ss"
    }

    var body: some View {
        ScrollViewReader { scrollView in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(logManager.logMessages) { log in
                        HStack(alignment: .top) {
                            Text("[\(formattedDate(log.timestamp))]")
                                .font(.footnote)
                                .foregroundColor(Color.secondary)  // Dynamic color
                            Text("[\(log.level.description)]")
                                .font(.footnote)
                                .bold()
                                .foregroundColor(levelColor(log.level))
                            Text(log.message)
                                .font(.body)
                                .padding(.leading, 4)
                                .foregroundColor(Color.primary)  // Dynamic color
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(backgroundColor(log.level))
                        .padding(.vertical, 2)
                    }
                }
                .onChange(of: logManager.logMessages) { newMessages, _ in
                    if let last = newMessages.last {
                        DispatchQueue.main.async {
                            withAnimation {
                                scrollView.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }
            }
        }
        .frame(minWidth: 500, minHeight: 300)  // Set a better initial size
        .padding()
        #if os(iOS)
            .background(Color(UIColor.systemBackground))  // Dynamic background color for iOS
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
