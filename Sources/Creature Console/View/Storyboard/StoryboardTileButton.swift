import Common
import SwiftUI

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

/// The visual for a single storyboard tile — a tinted rounded rectangle with an SF Symbol and a
/// label. Shared by the editor (where it's draggable/selectable) and the perform view (where it's a
/// button). `highlighted` draws a live-state glow (e.g. a live-control creature being streamed to).
struct StoryboardTileButton: View {
    let tile: StoryboardTile
    var isSelected: Bool = false
    var highlighted: Bool = false

    var body: some View {
        let tint = highlighted ? Color.green : Color(storyboardHex: tile.tintColorHex)
        VStack(spacing: 6) {
            Image(systemName: tile.sfSymbol)
                .font(.system(size: 30, weight: .semibold))
            Text(tile.label)
                .font(.headline)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(8)
        // Liquid Glass: a tinted, interactive glass slab (the tile reads as a glowing button on
        // the dark perform canvas). Live tiles glow green.
        .glassEffect(
            .regular.tint(tint.opacity(highlighted ? 0.75 : 0.55)).interactive(),
            in: .rect(cornerRadius: 16)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    isSelected ? Color.white : Color.white.opacity(0.18),
                    lineWidth: isSelected ? 3 : 1)
        )
        // Make the whole slab tappable/clickable, not just the glyph + label.
        .contentShape(.rect(cornerRadius: 16, style: .continuous))
        .shadow(color: highlighted ? .green.opacity(0.6) : .clear, radius: highlighted ? 12 : 0)
    }
}

extension Color {
    /// Build a `Color` from a `#RRGGBB` storyboard hex string (defaults to a blue on bad input).
    init(storyboardHex hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# ")).uppercased()
        var value: UInt64 = 0
        guard cleaned.count == 6, Scanner(string: cleaned).scanHexInt64(&value) else {
            self = Color(.sRGB, red: 0.04, green: 0.52, blue: 1.0, opacity: 1)
            return
        }
        self = Color(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255.0,
            green: Double((value >> 8) & 0xFF) / 255.0,
            blue: Double(value & 0xFF) / 255.0,
            opacity: 1)
    }

    /// Convert to a `#RRGGBB` hex string for persistence.
    func storyboardHexString() -> String {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        #if canImport(UIKit)
            UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        #elseif canImport(AppKit)
            let ns = NSColor(self).usingColorSpace(.sRGB) ?? NSColor(self)
            ns.getRed(&r, green: &g, blue: &b, alpha: &a)
        #endif
        return String(
            format: "#%02X%02X%02X",
            Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }
}
