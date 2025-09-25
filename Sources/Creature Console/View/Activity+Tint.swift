import SwiftUI

#if canImport(GameController)
    import GameController
#endif
#if os(iOS) || os(tvOS)
    import UIKit
#endif
#if os(macOS)
    import AppKit
#endif

extension Activity {
    /// Unified UI tint color using system dynamic colors.
    /// Update this mapping to change app-wide semantics.
    var tintColor: Color {
        switch self {
        case .idle:
            return .blue
        case .streaming:
            return .green
        case .recording:
            return .red
        case .preparingToRecord:
            return .yellow
        case .playingAnimation:
            return .purple
        case .connectingToServer:
            return .pink
        }
    }

    #if canImport(GameController)
        /// Game controller light color derived from the same activity mapping as `tintColor`.
        /// We resolve the corresponding platform system color to concrete RGB components.
        /// If resolution fails, we fall back to curated sRGB approximations of system colors.
        var controllerLightColor: GCColor {
            #if os(iOS) || os(tvOS)
                // Map to the exact system UIColors that correspond to SwiftUI's dynamic Colors
                let uiColor: UIColor = {
                    switch self {
                    case .idle: return .systemBlue
                    case .streaming: return .systemGreen
                    case .recording: return .systemRed
                    case .preparingToRecord: return .systemYellow
                    case .playingAnimation: return .systemPurple
                    case .connectingToServer: return .systemPink
                    }
                }()
                var r: CGFloat = 0
                var g: CGFloat = 0
                var b: CGFloat = 0
                var a: CGFloat = 0
                if uiColor.getRed(&r, green: &g, blue: &b, alpha: &a) {
                    return GCColor(red: Float(r), green: Float(g), blue: Float(b))
                }
            #elseif os(macOS)
                // Map to AppKit system colors and convert to device RGB
                let nsColor: NSColor = {
                    switch self {
                    case .idle: return .systemBlue
                    case .streaming: return .systemGreen
                    case .recording: return .systemRed
                    case .preparingToRecord: return .systemYellow
                    case .playingAnimation: return .systemPurple
                    case .connectingToServer: return .systemPink
                    }
                }()
                let rgb = nsColor.usingColorSpace(.deviceRGB) ?? nsColor
                return GCColor(
                    red: Float(rgb.redComponent), green: Float(rgb.greenComponent),
                    blue: Float(rgb.blueComponent))
            #endif

            // Fallback: curated sRGB approximations of system colors
            switch self {
            case .idle:
                return GCColor(red: 0.0, green: 0.478, blue: 1.0)  // systemBlue approx
            case .streaming:
                return GCColor(red: 0.203, green: 0.780, blue: 0.349)  // systemGreen approx
            case .recording:
                return GCColor(red: 1.0, green: 0.231, blue: 0.188)  // systemRed approx
            case .preparingToRecord:
                return GCColor(red: 1.0, green: 0.8, blue: 0.0)  // systemYellow approx
            case .playingAnimation:
                return GCColor(red: 0.686, green: 0.321, blue: 0.870)  // systemPurple approx
            case .connectingToServer:
                return GCColor(red: 1.0, green: 0.176, blue: 0.333)  // systemPink approx
            }
        }
    #endif
}
