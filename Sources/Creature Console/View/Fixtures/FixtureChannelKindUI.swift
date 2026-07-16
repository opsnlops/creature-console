import Common
import SwiftUI

/// Presentation helpers for `FixtureChannel.kind` — friendly names and color swatches so
/// the UI never shows raw wire strings like `color_red` or `master_dimmer`.
enum FixtureChannelKindUI {

    static func displayName(for kind: String) -> String {
        switch kind {
        case FixtureChannelKind.colorRed: return "Red"
        case FixtureChannelKind.colorGreen: return "Green"
        case FixtureChannelKind.colorBlue: return "Blue"
        case FixtureChannelKind.colorWhite: return "White"
        case FixtureChannelKind.colorAmber: return "Amber"
        case FixtureChannelKind.colorLime: return "Lime"
        case FixtureChannelKind.colorUV: return "UV"
        case FixtureChannelKind.masterDimmer: return "Master Dimmer"
        case FixtureChannelKind.strobe: return "Strobe"
        case FixtureChannelKind.pan: return "Pan"
        case FixtureChannelKind.tilt: return "Tilt"
        case FixtureChannelKind.gobo: return "Gobo"
        case FixtureChannelKind.generic: return "Generic"
        default: return kind
        }
    }

    /// The emitter's color for color-role kinds, `nil` for everything else.
    static func swatch(for kind: String) -> Color? {
        switch kind {
        case FixtureChannelKind.colorRed: return .red
        case FixtureChannelKind.colorGreen: return .green
        case FixtureChannelKind.colorBlue: return .blue
        case FixtureChannelKind.colorWhite: return .white
        case FixtureChannelKind.colorAmber: return Color(red: 1.0, green: 0.75, blue: 0.0)
        case FixtureChannelKind.colorLime: return Color(red: 0.72, green: 1.0, blue: 0.16)
        case FixtureChannelKind.colorUV: return Color(red: 0.45, green: 0.1, blue: 0.9)
        default: return nil
        }
    }
}

/// A small filled circle showing a channel kind's emitter color, or nothing for
/// non-color kinds. Sized to sit inline with captions and picker rows.
struct ChannelKindSwatch: View {
    let kind: String

    var body: some View {
        if let color = FixtureChannelKindUI.swatch(for: kind) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
                .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 0.5))
        }
    }
}

/// One channel's slider + numeric field + hex readout, shared by the live control panel
/// and the pattern value editor so the row reads (and behaves) identically in both.
/// The kind swatch makes it obvious which emitter each slider drives.
struct FixtureChannelSliderRow: View {
    let channel: FixtureChannel
    @Binding var value: UInt8

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            HStack(spacing: 6) {
                ChannelKindSwatch(kind: channel.kind)
                Text(channel.name)
                    .font(.system(.body, design: .monospaced))
            }
            .frame(width: 110, alignment: .leading)

            Slider(
                value: Binding<Double>(
                    get: { Double(value) },
                    set: { value = UInt8(clamping: Int($0.rounded())) }
                ),
                in: 0...255,
                step: 1
            )

            TextField(
                "0",
                value: Binding<Int>(
                    get: { Int(value) },
                    set: { value = UInt8(clamping: max(0, min(255, $0))) }
                ),
                format: .number
            )
            .textFieldStyle(.roundedBorder)
            .frame(width: 60)

            Text("0x\(String(value, radix: 16, uppercase: true))")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .leading)
        }
    }
}
