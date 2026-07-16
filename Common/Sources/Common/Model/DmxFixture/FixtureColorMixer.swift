import Foundation

/// Maps an RGB color onto a fixture's color-role channels — the single place the
/// RGB → RGB(W/L/A) mixing math lives.
///
/// **Every color-role channel gets an explicit value.** This is load-bearing: within a
/// live session the server holds any channel *not* named in a `setLive` call at its
/// previous value, so an engine that wrote only red/green/blue would leave a lime or
/// white emitter blazing from an earlier "All On" and wash out the picked color.
///
/// The extra-emitter math is a deliberately simple, predictable approximation (these are
/// party lights, not a colorimeter):
/// - `color_white` = min(r, g, b) — the achromatic content; renders whites and pastels
///   brighter and truer on RGBW hardware.
/// - `color_lime` = min(r, g) — the yellow-green content. Lime (~560 nm) exists to boost
///   exactly this band: full for yellows, partial for oranges/warm whites, and zero for
///   pure red, green, or blue, which the RGB emitters already render well.
/// - `color_amber` = min(r, g) — the same yellow content read; amber warms it.
/// - `color_uv` = 0 — picking a color must never blast UV as a side effect.
public enum FixtureColorMixer {

    /// Compute per-channel values for `color` (as 0–255 RGB) across `channels`.
    /// Channels with no color role (dimmer, strobe, pan, …) are not included.
    public static func values(
        red: UInt8, green: UInt8, blue: UInt8, channels: [FixtureChannel]
    ) -> [FixturePatternValue] {
        let white = min(red, green, blue)
        let lime = min(red, green)

        var result: [FixturePatternValue] = []
        for channel in channels {
            let value: UInt8?
            switch channel.kind {
            case FixtureChannelKind.colorRed: value = red
            case FixtureChannelKind.colorGreen: value = green
            case FixtureChannelKind.colorBlue: value = blue
            case FixtureChannelKind.colorWhite: value = white
            case FixtureChannelKind.colorLime: value = lime
            case FixtureChannelKind.colorAmber: value = lime
            case FixtureChannelKind.colorUV: value = 0
            default: value = nil
            }
            if let value {
                result.append(FixturePatternValue(channel: channel.name, value: value))
            }
        }
        return result
    }
}
