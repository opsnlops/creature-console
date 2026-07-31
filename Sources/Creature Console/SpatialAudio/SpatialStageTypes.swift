#if os(macOS)
    import Foundation

    struct SpatialStagePlacement: Codable, Equatable, Identifiable, Sendable {
        var creatureID: String
        var creatureName: String
        var audioChannel: Int
        var x: Float
        var y: Float
        var z: Float
        var gain: Float
        var isMuted: Bool

        var id: String { creatureID }

        init(
            creatureID: String,
            creatureName: String,
            audioChannel: Int,
            x: Float,
            y: Float = 1.4,
            z: Float,
            gain: Float = 1,
            isMuted: Bool = false
        ) {
            self.creatureID = creatureID
            self.creatureName = creatureName
            self.audioChannel = audioChannel
            self.x = x
            self.y = y
            self.z = z
            self.gain = gain
            self.isMuted = isMuted
        }
    }

    struct SpatialStageLayout: Codable, Equatable, Sendable {
        static let currentVersion = 2

        var version = currentVersion
        var stageWidth: Float = 10
        var stageDepth: Float = 6
        var listenerX: Float = 0
        var listenerY: Float = 1.6
        var listenerZ: Float = 2
        var listenerYaw: Float = 0
        var monitoringDelayMilliseconds = 10
        var backgroundMusicGain: Float = 0.7
        var reverbBlend: Float = 0.08
        var placements: [SpatialStagePlacement] = []
        var excludedCreatureIDs: Set<String> = []

        mutating func reconcile(with creatures: [SpatialStageCreature]) {
            let validCreatures = creatures.filter {
                (1...16).contains($0.audioChannel) && !excludedCreatureIDs.contains($0.id)
            }
            let existingByID = Dictionary(
                uniqueKeysWithValues: placements.map { ($0.creatureID, $0) })
            let count = max(validCreatures.count, 1)

            placements = validCreatures.enumerated().map { index, creature in
                if var existing = existingByID[creature.id] {
                    existing.creatureName = creature.name
                    existing.audioChannel = creature.audioChannel
                    return existing
                }

                let fraction = Float(index + 1) / Float(count + 1)
                return SpatialStagePlacement(
                    creatureID: creature.id,
                    creatureName: creature.name,
                    audioChannel: creature.audioChannel,
                    x: (fraction - 0.5) * stageWidth * 0.8,
                    z: -stageDepth * 0.45
                )
            }
        }

        mutating func removeCreature(id: String) {
            excludedCreatureIDs.insert(id)
            placements.removeAll { $0.creatureID == id }
        }

        mutating func restoreCreature(id: String, from creatures: [SpatialStageCreature]) {
            excludedCreatureIDs.remove(id)
            reconcile(with: creatures)
        }

        mutating func migrateToCurrentVersion() {
            if version < 2, monitoringDelayMilliseconds == 80 {
                monitoringDelayMilliseconds = 10
            }
            version = Self.currentVersion
        }

        private enum CodingKeys: String, CodingKey {
            case version
            case stageWidth
            case stageDepth
            case listenerX
            case listenerY
            case listenerZ
            case listenerYaw
            case monitoringDelayMilliseconds
            case backgroundMusicGain
            case reverbBlend
            case placements
            case excludedCreatureIDs
        }

        init() {}

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            version =
                try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
            stageWidth = try container.decodeIfPresent(Float.self, forKey: .stageWidth) ?? 10
            stageDepth = try container.decodeIfPresent(Float.self, forKey: .stageDepth) ?? 6
            listenerX = try container.decodeIfPresent(Float.self, forKey: .listenerX) ?? 0
            listenerY = try container.decodeIfPresent(Float.self, forKey: .listenerY) ?? 1.6
            listenerZ = try container.decodeIfPresent(Float.self, forKey: .listenerZ) ?? 2
            listenerYaw = try container.decodeIfPresent(Float.self, forKey: .listenerYaw) ?? 0
            monitoringDelayMilliseconds =
                try container.decodeIfPresent(Int.self, forKey: .monitoringDelayMilliseconds) ?? 10
            backgroundMusicGain =
                try container.decodeIfPresent(Float.self, forKey: .backgroundMusicGain) ?? 0.7
            reverbBlend =
                try container.decodeIfPresent(Float.self, forKey: .reverbBlend) ?? 0.08
            placements =
                try container.decodeIfPresent([SpatialStagePlacement].self, forKey: .placements)
                ?? []
            excludedCreatureIDs =
                try container.decodeIfPresent(Set<String>.self, forKey: .excludedCreatureIDs) ?? []
        }
    }

    struct SpatialStageCreature: Equatable, Identifiable, Sendable {
        let id: String
        let name: String
        let audioChannel: Int
    }

    enum SpatialStageInputMode: String, CaseIterable, Identifiable, Sendable {
        case live
        case simulation

        var id: String { rawValue }

        var label: String {
            switch self {
            case .live:
                "Live RTP"
            case .simulation:
                "Simulation"
            }
        }
    }

    enum SpatialStageConnectionState: Equatable, Sendable {
        case stopped
        case starting
        case waitingForAudio
        case playing
        case paused
        case failed(String)

        var label: String {
            switch self {
            case .stopped:
                "Stopped"
            case .starting:
                "Starting"
            case .waitingForAudio:
                "Waiting for audio"
            case .playing:
                "Playing"
            case .paused:
                "Paused"
            case .failed(let message):
                message
            }
        }
    }

    struct SpatialChannelDiagnostics: Equatable, Identifiable, Sendable {
        let channel: Int
        var packetsReceived: UInt64 = 0
        var invalidPackets: UInt64 = 0
        var concealedFrames: UInt64 = 0
        var fecFrames: UInt64 = 0
        var level: Float = 0
        var lastPacketDate: Date?

        var id: Int { channel }
    }

    struct SpatialStageDiagnostics: Equatable, Sendable {
        var state: SpatialStageConnectionState = .stopped
        var bufferedMilliseconds: Double = 0
        var outputLatencyMilliseconds: Double = 0
        var rtcpReportsReceived: UInt64 = 0
        var rtcpClockValid = false
        var channels: [SpatialChannelDiagnostics] = []
        var simulationPosition: TimeInterval = 0
        var simulationDuration: TimeInterval = 0
    }

    enum SpatialAudioLevel {
        static func rootMeanSquare(of samples: [Float]) -> Float {
            var energy = 0.0
            var finiteSampleCount = 0

            for sample in samples where sample.isFinite {
                let value = Double(sample)
                energy += value * value
                finiteSampleCount += 1
            }

            guard finiteSampleCount > 0, energy.isFinite else {
                return 0
            }
            let rootMeanSquare = sqrt(energy / Double(finiteSampleCount))
            return rootMeanSquare.isFinite ? Float(rootMeanSquare) : 0
        }

        static func meterLevel(for rootMeanSquare: Float) -> Double {
            guard rootMeanSquare.isFinite else {
                return 0
            }
            return min(max(Double(rootMeanSquare) * 8, 0), 1)
        }
    }

    enum SpatialStageLayoutStore {
        private static let key = "spatialStageLayout.v1"

        static func load() -> SpatialStageLayout {
            guard
                let data = UserDefaults.standard.data(forKey: key),
                var layout = try? JSONDecoder().decode(SpatialStageLayout.self, from: data),
                layout.version <= SpatialStageLayout.currentVersion
            else {
                return SpatialStageLayout()
            }
            let storedLayout = layout
            layout.migrateToCurrentVersion()
            if layout != storedLayout {
                save(layout)
            }
            return layout
        }

        static func save(_ layout: SpatialStageLayout) {
            guard let data = try? JSONEncoder().encode(layout) else {
                return
            }
            UserDefaults.standard.set(data, forKey: key)
        }
    }
#endif
