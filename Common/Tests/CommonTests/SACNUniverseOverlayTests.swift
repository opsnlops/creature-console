import Testing

@testable import Common

@Suite("SACN universe overlay builder")
struct SACNUniverseOverlayTests {

    private func creature(
        id: String = "creature-1",
        name: String = "Beaky",
        channelOffset: Int = 10,
        mouthSlot: Int = 0,
        inputs: [Input] = []
    ) -> Creature {
        Creature(
            id: id,
            name: name,
            channelOffset: channelOffset,
            mouthSlot: mouthSlot,
            audioChannel: 0,
            inputs: inputs
        )
    }

    private func input(_ name: String, slot: UInt16) -> Input {
        Input(name: name, slot: slot, width: 1, joystickAxis: 0)
    }

    private func fixture(
        id: String = "fixture-1",
        name: String = "Stage Left Spot",
        type: FixtureType = .light,
        channelOffset: UInt16 = 100,
        assignedUniverse: UInt32? = 1,
        channels: [FixtureChannel] = [
            FixtureChannel(offset: 0, name: "red", kind: FixtureChannelKind.colorRed),
            FixtureChannel(offset: 1, name: "green", kind: FixtureChannelKind.colorGreen),
            FixtureChannel(offset: 2, name: "blue", kind: FixtureChannelKind.colorBlue),
        ]
    ) -> DmxFixture {
        DmxFixture(
            id: id,
            name: name,
            type: type,
            channelOffset: channelOffset,
            assignedUniverse: assignedUniverse,
            channels: channels
        )
    }

    @Test("maps fixture channels onto absolute slots")
    func mapsFixtureChannelsOntoAbsoluteSlots() {
        let overlay = SACNUniverseOverlayBuilder.build(
            creatures: [],
            fixtures: [fixture()],
            universe: 1
        )

        #expect(overlay.slotOwners[100]?.first?.label == "red")
        #expect(overlay.slotOwners[101]?.first?.label == "green")
        #expect(overlay.slotOwners[102]?.first?.label == "blue")
        #expect(overlay.slotOwners[103] == nil)
        #expect(overlay.slotOwners[100]?.first?.kind == .fixture)
        #expect(overlay.slotOwners[100]?.first?.ownerName == "Stage Left Spot")
    }

    @Test("maps creature inputs and the mouth slot")
    func mapsCreatureInputsAndMouthSlot() {
        let overlay = SACNUniverseOverlayBuilder.build(
            creatures: [
                creature(
                    channelOffset: 10,
                    mouthSlot: 5,
                    inputs: [input("neck", slot: 0), input("beak", slot: 1)]
                )
            ],
            fixtures: [],
            universe: 1
        )

        #expect(overlay.slotOwners[10]?.first?.label == "neck")
        #expect(overlay.slotOwners[11]?.first?.label == "beak")
        #expect(overlay.slotOwners[15]?.first?.label == "Mouth")
        #expect(overlay.slotOwners[10]?.first?.kind == .creature)
        #expect(overlay.creatures.first?.slotCount == 3)
        #expect(overlay.creatures.first?.slotRange == 10...15)
    }

    @Test("a creature with no mouth slot doesn't claim one")
    func creatureWithoutMouthSlotClaimsNothingExtra() {
        let overlay = SACNUniverseOverlayBuilder.build(
            creatures: [
                creature(channelOffset: 10, mouthSlot: 0, inputs: [input("neck", slot: 0)])
            ],
            fixtures: [],
            universe: 1
        )

        #expect(overlay.slotOwners.count == 1)
        #expect(overlay.creatures.first?.slotCount == 1)
    }

    @Test("drops fixtures patched to a different universe")
    func dropsFixturesFromOtherUniverses() {
        let overlay = SACNUniverseOverlayBuilder.build(
            creatures: [],
            fixtures: [fixture(assignedUniverse: 2)],
            universe: 1
        )

        #expect(overlay.slotOwners.isEmpty)
        #expect(overlay.fixtures.isEmpty)
    }

    @Test("lists unassigned fixtures in the legend without claiming slots")
    func unassignedFixtureIsListedButClaimsNoSlots() {
        let overlay = SACNUniverseOverlayBuilder.build(
            creatures: [],
            fixtures: [fixture(assignedUniverse: nil)],
            universe: 1
        )

        #expect(overlay.slotOwners.isEmpty)
        #expect(overlay.fixtures.count == 1)
        #expect(overlay.fixtures.first?.assignedUniverse == nil)
        #expect(overlay.fixtures.first?.slotRange == nil)
        #expect(overlay.fixtures.first?.slotCount == 0)
        #expect(overlay.fixtures.first?.fixtureType == .light)
    }

    @Test("ignores channels that overflow the universe")
    func ignoresChannelsPastTheEndOfTheUniverse() {
        let overlay = SACNUniverseOverlayBuilder.build(
            creatures: [],
            fixtures: [
                fixture(
                    channelOffset: 511,
                    channels: [
                        FixtureChannel(offset: 0, name: "red", kind: FixtureChannelKind.colorRed),
                        FixtureChannel(
                            offset: 1, name: "green", kind: FixtureChannelKind.colorGreen),
                        FixtureChannel(offset: 2, name: "blue", kind: FixtureChannelKind.colorBlue),
                    ]
                )
            ],
            universe: 1
        )

        #expect(overlay.slotOwners[511]?.first?.label == "red")
        #expect(overlay.slotOwners[512]?.first?.label == "green")
        #expect(overlay.slotOwners[513] == nil)
        #expect(overlay.fixtures.first?.slotCount == 2)
    }

    @Test("a slot patched twice keeps both owners")
    func overlappingPatchKeepsBothOwners() {
        let overlay = SACNUniverseOverlayBuilder.build(
            creatures: [creature(channelOffset: 100, inputs: [input("neck", slot: 0)])],
            fixtures: [fixture(channelOffset: 100)],
            universe: 1
        )

        let owners = overlay.slotOwners[100] ?? []
        #expect(owners.count == 2)
        #expect(owners.contains { $0.kind == .creature })
        #expect(owners.contains { $0.kind == .fixture })
    }

    @Test("every owner gets its own hue")
    func everyOwnerGetsADistinctHue() {
        let overlay = SACNUniverseOverlayBuilder.build(
            creatures: [
                creature(id: "c1", name: "Alpha", channelOffset: 1),
                creature(id: "c2", name: "Beta", channelOffset: 20),
            ],
            fixtures: [
                fixture(id: "f1", name: "Spot One", channelOffset: 200),
                fixture(id: "f2", name: "Spot Two", channelOffset: 300),
            ],
            universe: 1
        )

        let hues = (overlay.creatures + overlay.fixtures).map(\.hue)
        #expect(hues.count == 4)
        #expect(Set(hues).count == 4)
        #expect(hues.allSatisfy { (0.0..<1.0).contains($0) })
    }

    @Test("hue assignment is stable across rebuilds regardless of input order")
    func hueAssignmentIsStable() {
        let alpha = creature(id: "c1", name: "Alpha", channelOffset: 1)
        let beta = creature(id: "c2", name: "Beta", channelOffset: 20)

        let forward = SACNUniverseOverlayBuilder.build(
            creatures: [alpha, beta], fixtures: [], universe: 1)
        let reversed = SACNUniverseOverlayBuilder.build(
            creatures: [beta, alpha], fixtures: [], universe: 1)

        #expect(forward.creatures.map(\.hue) == reversed.creatures.map(\.hue))
        #expect(forward.creatures.map(\.id) == ["c1", "c2"])
    }

    @Test("slot owner ids are unique so SwiftUI can diff them")
    func slotOwnerIdsAreUnique() {
        let overlay = SACNUniverseOverlayBuilder.build(
            creatures: [
                creature(
                    channelOffset: 10, mouthSlot: 2,
                    inputs: [input("neck", slot: 0), input("beak", slot: 1)])
            ],
            fixtures: [fixture(channelOffset: 10)],
            universe: 1
        )

        let ids = overlay.slotOwners.values.flatMap { $0 }.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("empty inputs produce an empty overlay")
    func emptyInputsProduceEmptyOverlay() {
        let overlay = SACNUniverseOverlayBuilder.build(creatures: [], fixtures: [], universe: 1)

        #expect(overlay.slotOwners.isEmpty)
        #expect(overlay.creatures.isEmpty)
        #expect(overlay.fixtures.isEmpty)
    }

    @Test("fixture type display names")
    func fixtureTypeDisplayNames() {
        #expect(FixtureType.light.displayName == "Light")
        #expect(FixtureType.smokeMachine.displayName == "Smoke Machine")
        #expect(FixtureType.fogger.displayName == "Fogger")
        #expect(FixtureType.generic.displayName == "Generic")
    }
}
