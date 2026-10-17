import Foundation
import Testing
import WorldCore

@testable import World_Viewer

@Suite("The house's scenes, as the birds are told them (#241)")
struct HousePanelTests {
    @Test("Asked for: offered and not set aside; everything else is set aside, by name")
    func sortsTheScenes() {
        let scenes = [
            HouseScene(name: "Sleepy Time", description: "dims the outside lights"),
            HouseScene(name: "Carport Motion", askable: false),
            HouseScene(name: "Old Party", description: "gone", offered: false),
            HouseScene(name: "Low Key"),
        ]
        #expect(HouseScenes.askable(scenes).map(\.name) == ["Low Key", "Sleepy Time"])
        #expect(HouseScenes.setAside(scenes).map(\.name) == ["Carport Motion", "Old Party"])
    }

    @Test("A scene round-trips in the World's shape")
    func shape() throws {
        let scene = HouseScene(
            name: "Movie Time", description: "the family room dark", askable: true,
            offered: true, updatedAt: Date(timeIntervalSince1970: 1_792_000_000),
            updatedBy: "wizard:april")
        let data = try WorldJSON.makeEncoder().encode(scene)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("\"updated_by\":\"wizard:april\""))
        #expect(try WorldJSON.makeDecoder().decode(HouseScene.self, from: data) == scene)
    }
}
