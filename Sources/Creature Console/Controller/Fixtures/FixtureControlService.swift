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

    /// Map a color onto a fixture's `color_red`/`green`/`blue` channels. Channels with no color role
    /// are left untouched. (Shared by the pattern editor and live control, so the mapping lives once.)
    static func colorValues(_ color: Color, channels: [FixtureChannel]) -> [FixturePatternValue] {
        guard let components = cgComponents(for: color), components.count >= 3 else { return [] }
        let r = byte(components[0])
        let g = byte(components[1])
        let b = byte(components[2])
        var values: [FixturePatternValue] = []
        for channel in channels {
            switch channel.kind {
            case FixtureChannelKind.colorRed:
                values.append(FixturePatternValue(channel: channel.name, value: r))
            case FixtureChannelKind.colorGreen:
                values.append(FixturePatternValue(channel: channel.name, value: g))
            case FixtureChannelKind.colorBlue:
                values.append(FixturePatternValue(channel: channel.name, value: b))
            default:
                break
            }
        }
        return values
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
        if let cg = color.cgColor { return cg.components }
        #if canImport(UIKit)
            return UIColor(color).cgColor.components
        #elseif canImport(AppKit)
            return NSColor(color).cgColor.components
        #else
            return nil
        #endif
    }
}
