import SwiftUI

struct ProcessingOverlayView: View {
    let message: String
    let progress: Double?

    var body: some View {
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
                        .foregroundColor(.secondary)
                }
            }
            .padding(16)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
        }
        .transition(.opacity)
    }
}

enum LayoutConstants {
    static let bottomToolbarInset: CGFloat = 80
}

extension View {
    @ViewBuilder
    func bottomToolbarInset() -> some View {
        #if os(macOS)
            self.safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: LayoutConstants.bottomToolbarInset)
            }
        #else
            self
        #endif
    }
}
