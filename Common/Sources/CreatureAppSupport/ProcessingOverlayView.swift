import SwiftUI

@available(macOS 26.0, iOS 26.0, *)
public struct ProcessingOverlayView: View {
    public let message: String
    public let progress: Double?

    public init(message: String, progress: Double?) {
        self.message = message
        self.progress = progress
    }

    public var body: some View {
        ZStack {
            Color.black.opacity(0.15).ignoresSafeArea()
            VStack(spacing: 10) {
                if let progress {
                    ProgressView(value: progress, total: 100)
                } else {
                    ProgressView()
                }
                Text(message)
                    .font(.callout)
                if let progress {
                    Text(String(format: "%.0f%%", progress))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
        }
        .transition(.opacity)
    }
}

public enum CreatureAppLayout {
    public static let bottomToolbarInset: CGFloat = 80
}

extension View {
    @ViewBuilder
    public func bottomToolbarInset() -> some View {
        #if os(macOS)
            self.safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: CreatureAppLayout.bottomToolbarInset)
            }
        #else
            self
        #endif
    }
}
