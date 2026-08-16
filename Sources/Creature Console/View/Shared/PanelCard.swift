import SwiftUI

extension View {
    /// A flat card surface: subtle fill plus a hairline stroke.
    ///
    /// The dialog editor uses this instead of `.glassEffect` for its panels and cards. Glass
    /// surfaces live-sample whatever is behind them, and the editor stacks an unbounded number
    /// of them (one per turn, plus nested cards inside every panel) in a scroll view — more GPU
    /// than a responsive UI can afford, especially with monitor windows compositing at the same
    /// time (#74). Glass stays where it earns its keep: buttons and small fixed chrome.
    func panelCard(cornerRadius: CGFloat = 12, tint: Color? = nil) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(tint?.opacity(0.14) ?? Color.primary.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(.quaternary, lineWidth: 1)
        )
    }
}
