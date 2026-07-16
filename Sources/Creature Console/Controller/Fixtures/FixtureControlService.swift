import Common
import CoreGraphics
import SwiftUI

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

/// Shared fixture control logic — the single source of truth for turning a fixture on/off, writing
/// a color, and triggering a pattern. Used by both the fixture editor's live panel and Storyboards,
/// so the channel-value math and color→RGB mapping exist exactly once.
enum FixtureControlService {

    /// Live control auto-blacks-out after this many ms (server cap is 10 min); we hold at the max.
    static let liveHoldMs: UInt32 = 600_000

    // MARK: - Value computation

    static func allOnValues(_ fixture: DmxFixture) -> [FixturePatternValue] {
        fixture.channels.map { FixturePatternValue(channel: $0.name, value: 255) }
    }

    static func allOffValues(_ fixture: DmxFixture) -> [FixturePatternValue] {
        fixture.channels.map { FixturePatternValue(channel: $0.name, value: 0) }
    }

    /// Map a color onto a fixture's color-role channels (red/green/blue/white/lime/amber/UV).
    /// Shared by the pattern editor and live control, so the mapping lives once — the actual
    /// mixing math is `FixtureColorMixer` in Common (tested there). Every color-role channel
    /// gets an explicit value; the server holds unnamed channels at their previous value
    /// within a live session, so partial writes would leave stale emitters washing out the color.
    static func colorValues(_ color: Color, channels: [FixtureChannel]) -> [FixturePatternValue] {
        guard let components = cgComponents(for: color), components.count >= 3 else { return [] }
        return FixtureColorMixer.values(
            red: byte(components[0]),
            green: byte(components[1]),
            blue: byte(components[2]),
            channels: channels)
    }

    // MARK: - Server actions

    @discardableResult
    static func turnOn(_ fixture: DmxFixture, server: CreatureServerClient = .shared) async
        -> Result<DmxFixture, ServerError>
    {
        await server.setFixtureLive(
            id: fixture.id, values: allOnValues(fixture), timeoutMs: liveHoldMs)
    }

    @discardableResult
    static func turnOff(_ fixture: DmxFixture, server: CreatureServerClient = .shared) async
        -> Result<DmxFixture, ServerError>
    {
        await server.setFixtureLive(
            id: fixture.id, values: allOffValues(fixture), timeoutMs: liveHoldMs)
    }

    @discardableResult
    static func setColor(
        _ color: Color, on fixture: DmxFixture, server: CreatureServerClient = .shared
    ) async -> Result<DmxFixture, ServerError> {
        var values = colorValues(color, channels: fixture.channels)
        guard !values.isEmpty else {
            return .failure(.dataFormatError("This fixture has no color channels."))
        }
        // Raise the master dimmer (if any) so the color is actually visible.
        for channel in fixture.channels where channel.kind == FixtureChannelKind.masterDimmer {
            values.append(FixturePatternValue(channel: channel.name, value: 255))
        }
        return await server.setFixtureLive(id: fixture.id, values: values, timeoutMs: liveHoldMs)
    }

    @discardableResult
    static func trigger(
        patternId: FixturePatternIdentifier, on fixtureId: DmxFixtureIdentifier,
        stopAfterMs: UInt32? = nil, server: CreatureServerClient = .shared
    ) async -> Result<DmxFixture, ServerError> {
        await server.triggerFixturePattern(
            fixtureId: fixtureId, patternId: patternId, stopAfterMs: stopAfterMs)
    }

    // MARK: - Color extraction (cross-platform)

    private static func byte(_ component: CGFloat) -> UInt8 {
        UInt8(clamping: Int((component * 255).rounded()))
    }

    private static func cgComponents(for color: Color) -> [CGFloat]? {
        let resolved: CGColor?
        if let cg = color.cgColor {
            resolved = cg
        } else {
            #if canImport(UIKit)
                resolved = UIColor(color).cgColor
            #elseif canImport(AppKit)
                resolved = NSColor(color).cgColor
            #else
                resolved = nil
            #endif
        }
        guard let cgColor = resolved else { return nil }

        // The system picker hands back Display P3 / extended-range (or grayscale) colors.
        // Convert to sRGB before reading components: P3 components for a saturated color are
        // smaller than their sRGB equivalents, so reading them raw makes every picker
        // round-trip slightly darker — and while dragging, the binding feeds each compressed
        // color back into the picker, whose brightness slider then creeps steadily downward.
        // (Conversion also normalizes grayscale colors to 4 RGBA components, so picking pure
        // white/gray swatches works instead of failing the component-count guard.)
        guard let srgb = CGColorSpace(name: CGColorSpace.sRGB),
            let converted = cgColor.converted(to: srgb, intent: .defaultIntent, options: nil)
        else { return cgColor.components }
        return converted.components
    }
}
