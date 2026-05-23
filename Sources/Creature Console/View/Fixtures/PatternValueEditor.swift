import Common
import SwiftUI

#if canImport(AppKit)
    import AppKit
#elseif canImport(UIKit)
    import UIKit
#endif

/// Per-pattern value editor. For `light`-type fixtures with channels declared as
/// `color_red` / `color_green` / `color_blue` (and optionally `color_white` /
/// `master_dimmer`), a `ColorPicker` is offered at the top that writes RGB(W) into
/// matching pattern values. Beneath that — *always* visible regardless of fixture type —
/// every declared channel gets a raw 0–255 slider + numeric field so the user can
/// hand-tweak any channel directly. The two stay in sync via the binding into
/// `fixture.patterns[patternIndex].values`.
struct PatternValueEditor: View {

    @Binding var fixture: Common.DmxFixture
    let patternIndex: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showColorPicker {
                colorSection
                Divider()
            }
            channelSlidersSection
        }
    }

    // MARK: - Color picker (light fixtures)

    private var showColorPicker: Bool {
        fixture.type == .light && (redChannel != nil || greenChannel != nil || blueChannel != nil)
    }

    /// Color picker is purely a *shortcut* — picking a color writes the matching RGB
    /// values into the raw sliders below. No duplicate sliders for `color_white` /
    /// `master_dimmer` here; those already appear once in the raw section, so adding
    /// "friendly" copies just confused the user (each move-one-update-both bound to
    /// the same channel).
    @ViewBuilder
    private var colorSection: some View {
        HStack(spacing: 12) {
            ColorPicker(
                "Color shortcut — writes RGB channels",
                selection: Binding<Color>(
                    get: { currentColor() },
                    set: { newColor in writeColorIntoValues(newColor) }
                ),
                supportsOpacity: false
            )

            Text(currentHexLabel())
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)

            Spacer()
        }
    }

    // MARK: - Raw per-channel sliders (every fixture type)

    @ViewBuilder
    private var channelSlidersSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("All channels (raw 0–255)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if fixture.channels.isEmpty {
                Text("Add channels to the fixture before configuring pattern values.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            ForEach(fixture.channels, id: \.name) { channel in
                HStack(alignment: .center, spacing: 8) {
                    Text(channel.name)
                        .frame(width: 100, alignment: .leading)
                        .font(.system(.body, design: .monospaced))
                    sliderRow(channelName: channel.name)
                }
            }
        }
    }

    /// Slider + numeric field for one channel. Reads the current value from the
    /// pattern's values array (defaults to 0 if not present) and writes back through
    /// the binding, creating a new `FixturePatternValue` entry on first write.
    private func sliderRow(channelName: String) -> some View {
        let value = currentValue(for: channelName)
        return HStack(spacing: 8) {
            Slider(
                value: Binding<Double>(
                    get: { Double(currentValue(for: channelName)) },
                    set: { setValue(UInt8(clamping: Int($0.rounded())), for: channelName) }
                ),
                in: 0...255,
                step: 1
            )

            TextField(
                "0",
                value: Binding<Int>(
                    get: { Int(currentValue(for: channelName)) },
                    set: { setValue(UInt8(clamping: max(0, min(255, $0))), for: channelName) }
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

    // MARK: - Channel lookups

    private var redChannel: FixtureChannel? {
        fixture.channels.first { $0.kind == FixtureChannelKind.colorRed }
    }

    private var greenChannel: FixtureChannel? {
        fixture.channels.first { $0.kind == FixtureChannelKind.colorGreen }
    }

    private var blueChannel: FixtureChannel? {
        fixture.channels.first { $0.kind == FixtureChannelKind.colorBlue }
    }

    // MARK: - Value get/set

    private func currentValue(for channelName: String) -> UInt8 {
        fixture.patterns[patternIndex].values.first { $0.channel == channelName }?.value ?? 0
    }

    private func setValue(_ value: UInt8, for channelName: String) {
        if let i = fixture.patterns[patternIndex].values.firstIndex(where: {
            $0.channel == channelName
        }) {
            fixture.patterns[patternIndex].values[i].value = value
        } else {
            fixture.patterns[patternIndex].values.append(
                FixturePatternValue(channel: channelName, value: value))
        }
    }

    // MARK: - Color round-trip

    private func currentColor() -> Color {
        let r = redChannel.map { Double(currentValue(for: $0.name)) / 255.0 } ?? 0
        let g = greenChannel.map { Double(currentValue(for: $0.name)) / 255.0 } ?? 0
        let b = blueChannel.map { Double(currentValue(for: $0.name)) / 255.0 } ?? 0
        return Color(red: r, green: g, blue: b)
    }

    private func currentHexLabel() -> String {
        let r = redChannel.map { currentValue(for: $0.name) } ?? 0
        let g = greenChannel.map { currentValue(for: $0.name) } ?? 0
        let b = blueChannel.map { currentValue(for: $0.name) } ?? 0
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    private func writeColorIntoValues(_ color: Color) {
        // CIColor gives us reliable component extraction across platforms.
        let cg = color.cgColor ?? platformCGColor(for: color)
        guard let components = cg?.components, components.count >= 3 else { return }
        let r = clampedByte(components[0])
        let g = clampedByte(components[1])
        let b = clampedByte(components[2])

        if let red = redChannel { setValue(r, for: red.name) }
        if let green = greenChannel { setValue(g, for: green.name) }
        if let blue = blueChannel { setValue(b, for: blue.name) }
    }

    private func clampedByte(_ raw: CGFloat) -> UInt8 {
        let scaled = (raw * 255).rounded()
        return UInt8(clamping: Int(scaled))
    }

    /// SwiftUI's `Color.cgColor` can be `nil` for system colors; fall back to the
    /// platform's bridged color which always resolves.
    private func platformCGColor(for color: Color) -> CGColor? {
        #if canImport(AppKit)
            return NSColor(color).cgColor
        #elseif canImport(UIKit)
            return UIColor(color).cgColor
        #else
            return nil
        #endif
    }
}
