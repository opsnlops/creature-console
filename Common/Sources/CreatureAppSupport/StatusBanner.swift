import SwiftUI

@available(macOS 26.0, iOS 26.0, *)
private struct StatusBannerModifier: ViewModifier {
    @Binding var message: String?
    let systemImage: String
    let tint: Color
    let duration: Duration
    let alignment: Alignment

    func body(content: Content) -> some View {
        content
            .overlay(alignment: alignment) {
                if let message {
                    Label(message, systemImage: systemImage)
                        .font(.callout)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .glassEffect(.regular.tint(tint.opacity(0.4)), in: .capsule)
                        .padding(24)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: message)
            .task(id: message) {
                guard message != nil else { return }
                try? await Task.sleep(for: duration)
                message = nil
            }
    }
}

extension View {
    @available(macOS 26.0, iOS 26.0, *)
    public func statusBanner(
        _ message: Binding<String?>,
        systemImage: String = "checkmark.circle.fill",
        tint: Color = .green,
        duration: Duration = .seconds(4),
        alignment: Alignment = .bottom
    ) -> some View {
        modifier(
            StatusBannerModifier(
                message: message,
                systemImage: systemImage,
                tint: tint,
                duration: duration,
                alignment: alignment
            ))
    }
}
