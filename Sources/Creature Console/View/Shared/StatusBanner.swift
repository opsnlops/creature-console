import SwiftUI

/// The one transient-confirmation banner: a tinted glass capsule that floats over the
/// content, then dismisses itself.
///
/// Replaces the hand-rolled banner/generation-counter implementations that had drifted apart
/// across AnimationTable, AnimationEditor, StoryboardEditor, DialogScriptEditor,
/// StoryboardPerformView, and SoundDataImporter. `.task(id:)` supersedes the manual
/// generation counters: a newer message cancels the older auto-dismiss for free.
///
/// ```swift
/// @State private var banner: String?
/// // ...
/// .statusBanner($banner)
/// // ...
/// banner = "Universe \(universe): \(message)"
/// ```
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
    /// Shows `message` as a transient glass banner whenever it becomes non-nil, clearing it
    /// automatically after `duration`. Setting a new message restarts the clock.
    func statusBanner(
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
