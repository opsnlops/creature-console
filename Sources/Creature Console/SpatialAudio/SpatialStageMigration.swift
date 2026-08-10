#if os(macOS)
    import Common
    import Foundation
    import OSLog

    /// The stage layout as it was stored in `UserDefaults` before stages became a server-side
    /// asset (issue #67).
    ///
    /// This type exists **only** to read that old value once and hand it to the server. Nothing
    /// writes it any more, so it deliberately carries no mutation helpers — the live document is
    /// `Common.Stage`, and keeping a second editable representation around is exactly the drift
    /// this migration exists to end.
    struct LegacySpatialStageLayout: Codable, Equatable, Sendable {

        /// The last version this format ever reached. Unrelated to `Stage.version`, which numbers
        /// the server's *coordinate frame* and is independently at 1 — same field name, different
        /// document. Conflating them would make a v1 stage look older than a v3 layout and get it
        /// silently discarded.
        static let finalVersion = 3

        struct Placement: Codable, Equatable, Sendable {
            var creatureID: String
            var creatureName: String
            var audioChannel: Int
            var x: Float
            var y: Float
            var z: Float
            var gain: Float
            var isMuted: Bool
        }

        var version: Int
        var listenerX: Float
        var listenerY: Float
        var listenerZ: Float
        var listenerYaw: Float
        var monitoringDelayMilliseconds: Int
        var commonPlayoutDelayMilliseconds: Int
        var backgroundMusicGain: Float
        var reverbBlend: Float
        var placements: [Placement]

        private enum CodingKeys: String, CodingKey {
            case version, listenerX, listenerY, listenerZ, listenerYaw
            case monitoringDelayMilliseconds, commonPlayoutDelayMilliseconds
            case backgroundMusicGain, reverbBlend, placements
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            version = try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.finalVersion
            listenerX = try container.decodeIfPresent(Float.self, forKey: .listenerX) ?? 0
            listenerY = try container.decodeIfPresent(Float.self, forKey: .listenerY) ?? 1.6
            listenerZ = try container.decodeIfPresent(Float.self, forKey: .listenerZ) ?? 2
            listenerYaw = try container.decodeIfPresent(Float.self, forKey: .listenerYaw) ?? 0
            monitoringDelayMilliseconds =
                try container.decodeIfPresent(Int.self, forKey: .monitoringDelayMilliseconds) ?? 10
            // Layout v1 shipped with an 80 ms placeholder before monitoring was synchronized to
            // the 10 ms RTP packet cadence. The deleted `SpatialStageLayout.migrateToCurrentVersion`
            // normalized this sentinel on load; retain that compatibility while decoding the
            // one-time server migration document.
            if version < 2, monitoringDelayMilliseconds == 80 {
                monitoringDelayMilliseconds = 10
            }
            commonPlayoutDelayMilliseconds =
                try container.decodeIfPresent(Int.self, forKey: .commonPlayoutDelayMilliseconds)
                ?? 20
            backgroundMusicGain =
                try container.decodeIfPresent(Float.self, forKey: .backgroundMusicGain) ?? 0.7
            reverbBlend = try container.decodeIfPresent(Float.self, forKey: .reverbBlend) ?? 0.08
            placements =
                try container.decodeIfPresent([Placement].self, forKey: .placements) ?? []
        }
    }

    /// Reads the pre-#67 `UserDefaults` layout and converts it into a server `Stage`.
    enum SpatialStageMigration {

        /// Where the layout was stored before stages moved to the server.
        static let legacyDefaultsKey = "spatialStageLayout.v1"
        /// Set once the legacy layout has been handed to the server, so a stage the operator later
        /// deletes on purpose doesn't get resurrected on the next launch.
        static let migrationCompletedKey = "spatialStageLayout.migratedToServer"

        private static let logger = Logger(
            subsystem: "io.opsnlops.CreatureConsole", category: "SpatialStageMigration")

        /// The legacy layout still sitting in `UserDefaults`, if there is one and it hasn't already
        /// been migrated.
        static func pendingLegacyLayout(
            defaults: UserDefaults = .standard
        ) -> LegacySpatialStageLayout? {
            guard !defaults.bool(forKey: migrationCompletedKey) else {
                return nil
            }
            guard let data = defaults.data(forKey: legacyDefaultsKey) else {
                return nil
            }
            do {
                return try JSONDecoder().decode(LegacySpatialStageLayout.self, from: data)
            } catch {
                // A layout we can't read isn't worth blocking startup over; the operator can
                // rebuild the stage by hand, and leaving the key in place keeps the old value
                // available for inspection.
                logger.warning(
                    "Could not decode the legacy stage layout: \(String(describing: error))")
                return nil
            }
        }

        static func markMigrated(defaults: UserDefaults = .standard) {
            defaults.set(true, forKey: migrationCompletedKey)
        }

        /// Convert a legacy layout into a `Stage` in the server's listener-at-the-origin frame.
        ///
        /// Two things the old format never recorded have to be invented here:
        ///
        /// * **Facing.** The layout had no per-creature heading, so each one is pointed back at the
        ///   listener — a cast arranged for an audience is addressing that audience. That is a
        ///   guess, but a legible one: it's obvious in the editor when it's wrong, in a way a flat
        ///   `0` for everybody would not be.
        /// * **Bounds.** The old frame had no ±5 m limit, so a wide layout can migrate outside the
        ///   box. Coordinates are clamped rather than allowed to fail the whole save, since the
        ///   server rejects a stage if any single placement is out of range.
        static func stage(
            from layout: LegacySpatialStageLayout,
            title: String = "Imported Stage"
        ) -> Stage {
            let listener = (x: layout.listenerX, y: layout.listenerY, z: layout.listenerZ)

            let placements = layout.placements.map { legacy -> StagePlacement in
                let moved = StageFrame.reorigin(
                    point: (x: legacy.x, y: legacy.y, z: legacy.z),
                    listener: listener,
                    listenerYaw: layout.listenerYaw)
                let position = (
                    x: StageFrame.clampToStage(moved.x),
                    y: StageFrame.clampToStage(moved.y),
                    z: StageFrame.clampToStage(moved.z)
                )
                return StagePlacement(
                    creatureID: legacy.creatureID,
                    creatureName: legacy.creatureName,
                    audioChannel: legacy.audioChannel,
                    x: position.x,
                    y: position.y,
                    z: position.z,
                    yaw: StageFrame.headingTowardListener(from: position),
                    gain: legacy.gain,
                    isMuted: legacy.isMuted)
            }

            return Stage(
                id: UUID(),
                title: title,
                notes: "Migrated from this Mac's local spatial-audio layout.",
                placements: placements,
                audio: StageAudioSettings(
                    monitoringDelayMilliseconds: layout.monitoringDelayMilliseconds,
                    commonPlayoutDelayMilliseconds: layout.commonPlayoutDelayMilliseconds,
                    backgroundMusicGain: layout.backgroundMusicGain,
                    reverbBlend: layout.reverbBlend))
        }
    }
#endif
