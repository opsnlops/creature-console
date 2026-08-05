import Foundation

/// Converting coordinates from the Console's old absolute stage frame into the server's
/// listener-at-the-origin frame.
///
/// The old frame parked the listener wherever the operator put them — typically `(0, 1.6, 2)` —
/// with the cast crammed into negative Z, and carried an explicit `listenerYaw`. The server's
/// frame puts the listener at `(0, 0, 0)` facing −Z, so a stage is expressed relative to the ears
/// that hear it and the same document can drive both the spatial mix and head aiming.
///
/// Moving between them is a translation followed by a rotation: subtract the listener's position,
/// then rotate the whole frame so the listener's heading becomes −Z.
public enum StageFrame {

    /// Re-express a point that was measured in the old absolute frame in the listener-at-origin
    /// frame.
    ///
    /// - Parameters:
    ///   - point: `(x, y, z)` in the old absolute frame.
    ///   - listener: where the listener stood in that frame.
    ///   - listenerYaw: which way they faced, in degrees, `0` meaning "already facing −Z".
    public static func reorigin(
        point: (x: Float, y: Float, z: Float),
        listener: (x: Float, y: Float, z: Float),
        listenerYaw: Float
    ) -> (x: Float, y: Float, z: Float) {
        let translatedX = point.x - listener.x
        let translatedY = point.y - listener.y
        let translatedZ = point.z - listener.z

        // Undo the listener's heading so their facing lands on −Z. With the default yaw of 0 this
        // is the identity and the whole conversion is the translation above.
        guard listenerYaw.isFinite, listenerYaw != 0 else {
            return (translatedX, translatedY, translatedZ)
        }
        let radians = -listenerYaw * .pi / 180
        let cosine = cos(radians)
        let sine = sin(radians)
        return (
            x: translatedX * cosine + translatedZ * sine,
            y: translatedY,
            z: -translatedX * sine + translatedZ * cosine
        )
    }

    /// The heading, in stage-frame degrees, that points from `point` back at the listener at the
    /// origin.
    ///
    /// Used when migrating a layout that never recorded which way anything faced: a cast arranged
    /// for an audience is addressing that audience, so "facing the listener" is a far better
    /// starting guess than a flat `0` — and it's visibly wrong in the editor if it isn't what the
    /// operator wants, which a silent `0` is not.
    public static func headingTowardListener(from point: (x: Float, y: Float, z: Float)) -> Float {
        // yaw 0 faces +Z and +90 faces +X, so the heading is atan2(Δx, Δz) toward the origin.
        guard point.x.isFinite, point.z.isFinite, point.x != 0 || point.z != 0 else {
            return 0
        }
        let degrees = atan2(-point.x, -point.z) * 180 / .pi
        return StagePlacement.normalizedYaw(degrees)
    }

    /// Clamp a coordinate into the ±5 m stage box.
    ///
    /// A migrated layout can land outside the box — the old frame had no such limit — and the
    /// server rejects the whole stage if any coordinate is out of range. Clamping keeps a
    /// migration from failing wholesale on one stray value; the editor shows where things ended up.
    public static func clampToStage(_ value: Float) -> Float {
        guard value.isFinite else { return 0 }
        return min(max(value, -StageLimits.coordinateLimit), StageLimits.coordinateLimit)
    }
}
