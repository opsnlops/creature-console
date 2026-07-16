import Foundation
import Testing

@testable import Common

@Suite("FixtureColorMixer")
struct FixtureColorMixerTests {

    /// Beaky's Light — the real RGBL fixture this engine exists for.
    private let rgblChannels = [
        FixtureChannel(offset: 0, name: "red", kind: FixtureChannelKind.colorRed),
        FixtureChannel(offset: 1, name: "green", kind: FixtureChannelKind.colorGreen),
        FixtureChannel(offset: 2, name: "blue", kind: FixtureChannelKind.colorBlue),
        FixtureChannel(offset: 3, name: "lime", kind: FixtureChannelKind.colorLime),
        FixtureChannel(offset: 4, name: "master", kind: FixtureChannelKind.masterDimmer),
    ]

    private func value(_ channel: String, in values: [FixturePatternValue]) -> UInt8? {
        values.first(where: { $0.channel == channel })?.value
    }

    @Test("RGB channels get the color's components by channel name")
    func rgbPassthrough() {
        let values = FixtureColorMixer.values(
            red: 10, green: 20, blue: 30, channels: rgblChannels)
        #expect(value("red", in: values) == 10)
        #expect(value("green", in: values) == 20)
        #expect(value("blue", in: values) == 30)
    }

    @Test("lime carries the yellow-green content: full for yellow, zero for pure primaries")
    func limeExtraction() {
        let yellow = FixtureColorMixer.values(
            red: 255, green: 255, blue: 0, channels: rgblChannels)
        #expect(value("lime", in: yellow) == 255)

        let orange = FixtureColorMixer.values(
            red: 255, green: 128, blue: 0, channels: rgblChannels)
        #expect(value("lime", in: orange) == 128)

        for pure in [(255, 0, 0), (0, 255, 0), (0, 0, 255)] {
            let values = FixtureColorMixer.values(
                red: UInt8(pure.0), green: UInt8(pure.1), blue: UInt8(pure.2),
                channels: rgblChannels)
            #expect(value("lime", in: values) == 0)
        }
    }

    @Test("every color-role channel gets an explicit value — none left to go stale")
    func noStaleColorChannels() {
        // The server holds channels not named in a live call at their previous value,
        // so a color write must name every color-role channel (and only those).
        let channels = [
            FixtureChannel(offset: 0, name: "r", kind: FixtureChannelKind.colorRed),
            FixtureChannel(offset: 1, name: "g", kind: FixtureChannelKind.colorGreen),
            FixtureChannel(offset: 2, name: "b", kind: FixtureChannelKind.colorBlue),
            FixtureChannel(offset: 3, name: "w", kind: FixtureChannelKind.colorWhite),
            FixtureChannel(offset: 4, name: "lime", kind: FixtureChannelKind.colorLime),
            FixtureChannel(offset: 5, name: "amber", kind: FixtureChannelKind.colorAmber),
            FixtureChannel(offset: 6, name: "uv", kind: FixtureChannelKind.colorUV),
            FixtureChannel(offset: 7, name: "dim", kind: FixtureChannelKind.masterDimmer),
            FixtureChannel(offset: 8, name: "strobe", kind: FixtureChannelKind.strobe),
        ]
        let values = FixtureColorMixer.values(red: 255, green: 0, blue: 0, channels: channels)
        let named = Set(values.map(\.channel))
        #expect(named == ["r", "g", "b", "w", "lime", "amber", "uv"])
    }

    @Test("white carries the achromatic content on RGBW")
    func whiteExtraction() {
        let channels = [
            FixtureChannel(offset: 0, name: "red", kind: FixtureChannelKind.colorRed),
            FixtureChannel(offset: 1, name: "green", kind: FixtureChannelKind.colorGreen),
            FixtureChannel(offset: 2, name: "blue", kind: FixtureChannelKind.colorBlue),
            FixtureChannel(offset: 3, name: "white", kind: FixtureChannelKind.colorWhite),
        ]
        let white = FixtureColorMixer.values(
            red: 255, green: 255, blue: 255, channels: channels)
        #expect(value("white", in: white) == 255)

        let pastelRed = FixtureColorMixer.values(
            red: 255, green: 200, blue: 200, channels: channels)
        #expect(value("white", in: pastelRed) == 200)

        let saturated = FixtureColorMixer.values(
            red: 255, green: 0, blue: 128, channels: channels)
        #expect(value("white", in: saturated) == 0)
    }

    @Test("UV is always driven to zero by a color write")
    func uvAlwaysZero() {
        let channels = [
            FixtureChannel(offset: 0, name: "red", kind: FixtureChannelKind.colorRed),
            FixtureChannel(offset: 1, name: "uv", kind: FixtureChannelKind.colorUV),
        ]
        let values = FixtureColorMixer.values(
            red: 255, green: 255, blue: 255, channels: channels)
        #expect(value("uv", in: values) == 0)
    }

    @Test("non-color channels are never included")
    func nonColorChannelsExcluded() {
        let values = FixtureColorMixer.values(
            red: 255, green: 255, blue: 255, channels: rgblChannels)
        #expect(value("master", in: values) == nil)
    }

    @Test("color_lime is a known kind")
    func limeKindRegistered() {
        #expect(FixtureChannelKind.all.contains(FixtureChannelKind.colorLime))
        #expect(FixtureChannelKind.colorLime == "color_lime")
    }
}
