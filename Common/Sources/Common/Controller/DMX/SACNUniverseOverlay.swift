import Foundation

/// Which kind of thing owns a DMX slot in the sACN universe overlay.
public enum SACNSlotOwnerKind: String, Codable, Sendable, Hashable, CaseIterable {
    case creature
    case fixture
}

/// One claim on a single DMX slot — a creature input (or its mouth) or a fixture channel.
///
/// `hue` is the owner's identity color as a 0..<1 hue. The builder hands out hues so the
/// grid and the legend can never disagree about who is what color; turning a hue into a
/// platform `Color` is the UI layer's job (`Common` has to build on Linux, where there is
/// no SwiftUI).
public struct SACNSlotOwner: Identifiable, Hashable, Sendable {
    public let id: String
    public let kind: SACNSlotOwnerKind
    public let ownerID: String
    public let ownerName: String
    public let label: String
    public let hue: Double

    public init(
        id: String,
        kind: SACNSlotOwnerKind,
        ownerID: String,
        ownerName: String,
        label: String,
        hue: Double
    ) {
        self.id = id
        self.kind = kind
        self.ownerID = ownerID
        self.ownerName = ownerName
        self.label = label
        self.hue = hue
    }
}

/// One row in the monitor's overlay legend. Purely data — how it reads ("3 inputs" vs
/// "4 channels") is up to the view.
public struct SACNOverlayLegendEntry: Identifiable, Hashable, Sendable {
    public let id: String
    public let kind: SACNSlotOwnerKind
    public let name: String
    public let hue: Double
    public let slotRange: ClosedRange<Int>?
    public let slotCount: Int
    /// Fixtures only — `nil` for creatures.
    public let fixtureType: FixtureType?
    /// Fixtures only — the universe the fixture is patched to, `nil` when it isn't patched
    /// anywhere yet. Creatures don't carry a universe; they follow the console's active one.
    public let assignedUniverse: UInt32?

    public init(
        id: String,
        kind: SACNSlotOwnerKind,
        name: String,
        hue: Double,
        slotRange: ClosedRange<Int>?,
        slotCount: Int,
        fixtureType: FixtureType? = nil,
        assignedUniverse: UInt32? = nil
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.hue = hue
        self.slotRange = slotRange
        self.slotCount = slotCount
        self.fixtureType = fixtureType
        self.assignedUniverse = assignedUniverse
    }
}

/// Everything the sACN monitor needs to draw who owns what in one universe.
public struct SACNUniverseOverlay: Sendable {
    /// Keyed by 1-based DMX slot number, so it drops straight onto the monitor's grid.
    /// A slot can have more than one owner when two things are patched on top of each other.
    public let slotOwners: [Int: [SACNSlotOwner]]
    public let creatures: [SACNOverlayLegendEntry]
    public let fixtures: [SACNOverlayLegendEntry]

    public init(
        slotOwners: [Int: [SACNSlotOwner]],
        creatures: [SACNOverlayLegendEntry],
        fixtures: [SACNOverlayLegendEntry]
    ) {
        self.slotOwners = slotOwners
        self.creatures = creatures
        self.fixtures = fixtures
    }

    public static let empty = SACNUniverseOverlay(slotOwners: [:], creatures: [], fixtures: [])
}

/// Maps creatures and fixtures onto the DMX slots they occupy.
///
/// Both `Creature.channelOffset` and `DmxFixture.channelOffset` are 1-based DMX slot
/// numbers — the server hands them to `E131Server::setValues()` as the first slot to write
/// — so a creature input at `slot` lands on `channelOffset + slot`, and a fixture channel at
/// `offset` lands on `channelOffset + offset`.
public enum SACNUniverseOverlayBuilder {

    /// The addressable slots in a DMX universe, 1-based to match the monitor's grid.
    public static let slotRange = 1...512

    /// Golden-ratio hue walk: consecutive owners land far apart on the color wheel, and the
    /// sequence is stable as long as the sorted order is.
    private static let goldenRatio = 0.618_033_988_749_895

    /// Build the overlay for one universe.
    ///
    /// Creatures are always included — they have no universe of their own and follow the
    /// console's active universe. Fixtures are patched explicitly, so a fixture assigned to
    /// a *different* universe is dropped entirely; one that isn't assigned anywhere gets a
    /// legend row (so it's easy to notice it still needs patching) but claims no slots.
    public static func build(
        creatures: [Creature],
        fixtures: [DmxFixture],
        universe: UInt32
    ) -> SACNUniverseOverlay {

        let sortedCreatures = creatures.sorted { ($0.name, $0.id) < ($1.name, $1.id) }
        let relevantFixtures =
            fixtures
            .filter { $0.assignedUniverse == nil || $0.assignedUniverse == universe }
            .sorted { ($0.name, $0.id) < ($1.name, $1.id) }

        var currentHue = 0.0
        func nextHue() -> Double {
            currentHue = (currentHue + goldenRatio).truncatingRemainder(dividingBy: 1.0)
            return currentHue
        }

        var slotOwners: [Int: [SACNSlotOwner]] = [:]
        var creatureEntries: [SACNOverlayLegendEntry] = []
        var fixtureEntries: [SACNOverlayLegendEntry] = []

        func claim(_ slot: Int, _ owner: SACNSlotOwner, into slots: inout [Int]) {
            guard slotRange.contains(slot) else { return }
            slots.append(slot)
            slotOwners[slot, default: []].append(owner)
        }

        for creature in sortedCreatures {
            let hue = nextHue()
            var slots: [Int] = []

            for input in creature.inputs.sorted(by: { $0.slot < $1.slot }) {
                let slot = creature.channelOffset + Int(input.slot)
                claim(
                    slot,
                    SACNSlotOwner(
                        id: "\(creature.id):input:\(input.name):\(slot)",
                        kind: .creature,
                        ownerID: creature.id,
                        ownerName: creature.name,
                        label: input.name,
                        hue: hue
                    ),
                    into: &slots
                )
            }

            if creature.mouthSlot > 0 {
                let slot = creature.channelOffset + creature.mouthSlot
                claim(
                    slot,
                    SACNSlotOwner(
                        id: "\(creature.id):mouth:\(slot)",
                        kind: .creature,
                        ownerID: creature.id,
                        ownerName: creature.name,
                        label: "Mouth",
                        hue: hue
                    ),
                    into: &slots
                )
            }

            creatureEntries.append(
                SACNOverlayLegendEntry(
                    id: creature.id,
                    kind: .creature,
                    name: creature.name,
                    hue: hue,
                    slotRange: slots.range(),
                    slotCount: slots.count
                )
            )
        }

        for fixture in relevantFixtures {
            let hue = nextHue()
            var slots: [Int] = []

            if fixture.assignedUniverse == universe {
                for channel in fixture.channels.sorted(by: { $0.offset < $1.offset }) {
                    let slot = Int(fixture.channelOffset) + Int(channel.offset)
                    claim(
                        slot,
                        SACNSlotOwner(
                            id: "\(fixture.id):channel:\(channel.name):\(slot)",
                            kind: .fixture,
                            ownerID: fixture.id,
                            ownerName: fixture.name,
                            label: channel.name,
                            hue: hue
                        ),
                        into: &slots
                    )
                }
            }

            fixtureEntries.append(
                SACNOverlayLegendEntry(
                    id: fixture.id,
                    kind: .fixture,
                    name: fixture.name,
                    hue: hue,
                    slotRange: slots.range(),
                    slotCount: slots.count,
                    fixtureType: fixture.type,
                    assignedUniverse: fixture.assignedUniverse
                )
            )
        }

        return SACNUniverseOverlay(
            slotOwners: slotOwners,
            creatures: creatureEntries,
            fixtures: fixtureEntries
        )
    }
}

extension Array where Element == Int {
    /// The span this collection of slots covers, or `nil` when nothing was mapped.
    fileprivate func range() -> ClosedRange<Int>? {
        guard let low = self.min(), let high = self.max() else { return nil }
        return low...high
    }
}
