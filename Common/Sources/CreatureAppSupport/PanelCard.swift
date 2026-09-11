import SwiftUI

extension View {
    /// A lightweight shared card surface for repeatable or scrollable app content.
    public func panelCard(cornerRadius: CGFloat = 12, tint: Color? = nil) -> some View {
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
