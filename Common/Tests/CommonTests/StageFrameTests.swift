import Foundation
import Testing

@testable import Common

@Suite("Stage coordinate frame migration")
struct StageFrameTests {

    /// The Console's historical defaults: listener parked at the front edge, facing straight ahead.
    private let defaultListener: (x: Float, y: Float, z: Float) = (0, 1.6, 2)

    @Test("subtracts the listener position when the listener faces straight ahead")
    func translatesWithZeroYaw() {
        let result = StageFrame.reorigin(
            point: (x: -2.4, y: 1.4, z: -2.7), listener: defaultListener, listenerYaw: 0)

        #expect(result.x == -2.4)
        #expect(abs(result.y - (-0.2)) < 0.0001)
        #expect(abs(result.z - (-4.7)) < 0.0001)
    }

    @Test("puts the listener itself at the origin")
    func listenerLandsAtOrigin() {
        let result = StageFrame.reorigin(
            point: defaultListener, listener: defaultListener, listenerYaw: 0)

        #expect(abs(result.x) < 0.0001)
        #expect(abs(result.y) < 0.0001)
        #expect(abs(result.z) < 0.0001)
    }

    @Test("a bird on a low perch ends up below the listener's ears")
    func lowPerchIsNegativeY() {
        let result = StageFrame.reorigin(
            point: (x: 0, y: 1.2, z: -2.7), listener: defaultListener, listenerYaw: 0)
        #expect(result.y < 0)
    }

    @Test("rotating the listener's heading rotates the whole frame")
    func rotatesWithYaw() {
        // Directly in front of the listener in the old frame; a 90° turn should swing it onto an
        // axis rather than leaving it ahead.
        let result = StageFrame.reorigin(
            point: (x: 0, y: 1.6, z: 0), listener: (x: 0, y: 1.6, z: 2), listenerYaw: 90)

        #expect(abs(result.y) < 0.0001)
        // The point was 2 m along −Z; after a 90° frame rotation it lies 2 m along an X axis.
        #expect(abs(abs(result.x) - 2) < 0.0001)
        #expect(abs(result.z) < 0.0001)
    }

    @Test("a full turn is the same as no turn")
    func fullTurnIsIdentity() {
        let point: (x: Float, y: Float, z: Float) = (x: 1.5, y: 0.4, z: -3.0)
        let none = StageFrame.reorigin(point: point, listener: defaultListener, listenerYaw: 0)
        let full = StageFrame.reorigin(point: point, listener: defaultListener, listenerYaw: 360)

        #expect(abs(none.x - full.x) < 0.001)
        #expect(abs(none.z - full.z) < 0.001)
    }

    @Test("rotation preserves distance from the listener")
    func rotationPreservesDistance() {
        let point: (x: Float, y: Float, z: Float) = (x: 1.5, y: 1.6, z: -1.0)
        func distance(_ p: (x: Float, y: Float, z: Float)) -> Float {
            (p.x * p.x + p.y * p.y + p.z * p.z).squareRoot()
        }
        let straight = StageFrame.reorigin(
            point: point, listener: defaultListener, listenerYaw: 0)
        for yaw in [Float(37), 90, 180, -125] {
            let rotated = StageFrame.reorigin(
                point: point, listener: defaultListener, listenerYaw: yaw)
            #expect(abs(distance(straight) - distance(rotated)) < 0.001)
        }
    }

    @Test("survives a non-finite listener yaw instead of poisoning every coordinate")
    func toleratesNonFiniteYaw() {
        let result = StageFrame.reorigin(
            point: (x: 1, y: 1, z: 1), listener: defaultListener, listenerYaw: .nan)
        #expect(result.x.isFinite)
        #expect(result.y.isFinite)
        #expect(result.z.isFinite)
    }

    // MARK: - Facing

    @Test("a creature directly in front faces back toward the listener")
    func headingFromDirectlyAhead() {
        let heading = StageFrame.headingTowardListener(from: (x: 0, y: 0, z: -3))
        #expect(abs(heading) < 0.0001)
    }

    @Test("a creature off to the left turns toward the listener")
    func headingFromTheLeft() {
        // Left of the listener and in front: it should face right (positive yaw, toward +X).
        let heading = StageFrame.headingTowardListener(from: (x: -1.2, y: 0, z: -3))
        #expect(heading > 0)
        #expect(heading < 90)
    }

    @Test("a creature off to the right turns the other way")
    func headingFromTheRight() {
        let heading = StageFrame.headingTowardListener(from: (x: 1.2, y: 0, z: -3))
        #expect(heading < 0)
        #expect(heading > -90)
    }

    @Test("a creature beside the listener faces square across")
    func headingFromDirectlyBeside() {
        let heading = StageFrame.headingTowardListener(from: (x: -3, y: 0, z: 0))
        #expect(abs(heading - 90) < 0.0001)
    }

    @Test("a creature standing on the listener has no meaningful heading")
    func headingFromTheOrigin() {
        #expect(StageFrame.headingTowardListener(from: (x: 0, y: 0, z: 0)) == 0)
    }

    @Test("headings come back normalized")
    func headingsAreNormalized() {
        for x in stride(from: Float(-4), through: 4, by: 0.7) {
            for z in stride(from: Float(-4), through: 4, by: 0.7) {
                let heading = StageFrame.headingTowardListener(from: (x: x, y: 0, z: z))
                #expect(heading > -180)
                #expect(heading <= 180)
            }
        }
    }

    // MARK: - Clamping

    @Test("clamps coordinates into the stage box")
    func clampsOutOfRange() {
        #expect(StageFrame.clampToStage(9) == StageLimits.coordinateLimit)
        #expect(StageFrame.clampToStage(-9) == -StageLimits.coordinateLimit)
        #expect(StageFrame.clampToStage(2.5) == 2.5)
        #expect(StageFrame.clampToStage(.nan) == 0)
    }

    @Test("a migrated default layout lands inside the stage box")
    func defaultLayoutFitsInTheBox() {
        // The old defaults: a 10x6 stage with the cast at z ≈ -2.7 and the listener at z = 2.
        // That is 4.7 m in front of the listener — comfortably inside the ±5 m box, which is the
        // whole reason a straight translation is safe for the common case.
        let migrated = StageFrame.reorigin(
            point: (x: -4, y: 1.4, z: -2.7), listener: defaultListener, listenerYaw: 0)
        #expect(abs(migrated.x) <= StageLimits.coordinateLimit)
        #expect(abs(migrated.y) <= StageLimits.coordinateLimit)
        #expect(abs(migrated.z) <= StageLimits.coordinateLimit)
    }
}
