import Common
import Foundation
import Testing

@testable import Creature_Console

@Suite("Spatial PCM queue")
struct SpatialPCMQueueTests {
    @Test("writes and reads samples in order")
    func writesAndReadsInOrder() {
        let queue = SpatialPCMQueue(capacity: 8)
        #expect(queue.write([1, 2, 3, 4]))

        let output = read(4, from: queue)

        #expect(output == [1, 2, 3, 4])
        #expect(queue.availableFrames == 0)
    }

    @Test("a silent render tail does not skip later samples")
    func silentTailDoesNotSkipLaterSamples() {
        let queue = SpatialPCMQueue(capacity: 8)
        #expect(queue.write([1, 2, 3]))

        #expect(read(5, from: queue) == [1, 2, 3, 0, 0])
        #expect(queue.write([4, 5]))
        #expect(read(2, from: queue) == [4, 5])
    }

    @Test("wraps through fixed storage without reordering")
    func wrapsThroughStorage() {
        let queue = SpatialPCMQueue(capacity: 5)
        #expect(queue.write([1, 2, 3, 4]))
        #expect(read(3, from: queue) == [1, 2, 3])
        #expect(queue.write([5, 6, 7, 8]))

        #expect(read(5, from: queue) == [4, 5, 6, 7, 8])
    }

    private func read(_ count: Int, from queue: SpatialPCMQueue) -> [Float] {
        var output = [Float](repeating: -1, count: count)
        output.withUnsafeMutableBufferPointer { buffer in
            _ = queue.read(into: buffer.baseAddress!, frameCount: count)
        }
        return output
    }
}

@Suite("Spatial audio levels")
struct SpatialAudioLevelTests {
    @Test("RMS ignores non-finite samples")
    func rootMeanSquareIgnoresNonFiniteSamples() {
        let level = SpatialAudioLevel.rootMeanSquare(
            of: [0.25, -0.25, .nan, .infinity, -.infinity]
        )

        #expect(level == 0.25)
    }

    @Test("meter rejects non-finite levels")
    func meterRejectsNonFiniteLevels() {
        #expect(SpatialAudioLevel.meterLevel(for: .nan) == 0)
        #expect(SpatialAudioLevel.meterLevel(for: .infinity) == 0)
        #expect(SpatialAudioLevel.meterLevel(for: -.infinity) == 0)
    }
}

@Suite("Spatial stage layout")
struct SpatialStageLayoutTests {
    private let creatures = [
        SpatialStageCreature(id: "one", name: "One", audioChannel: 3),
        SpatialStageCreature(id: "two", name: "Two", audioChannel: 3),
    ]

    @Test("removed creatures stay excluded during reconciliation")
    func removedCreaturesStayExcludedDuringReconciliation() {
        var layout = SpatialStageLayout()
        layout.reconcile(with: creatures)

        layout.removeCreature(id: "two")
        layout.reconcile(with: creatures)

        #expect(layout.placements.map(\.creatureID) == ["one"])
        #expect(layout.excludedCreatureIDs == ["two"])
    }

    @Test("restoring a creature adds it to the stage again")
    func restoringCreatureAddsItToStageAgain() {
        var layout = SpatialStageLayout()
        layout.reconcile(with: creatures)
        layout.removeCreature(id: "two")

        layout.restoreCreature(id: "two", from: creatures)

        #expect(layout.placements.map(\.creatureID) == ["one", "two"])
        #expect(layout.excludedCreatureIDs.isEmpty)
    }

    @Test("layouts saved before exclusions decode with an empty roster override")
    func legacyLayoutDecodesWithEmptyRosterOverride() throws {
        let data = Data(
            #"{"version":1,"stageWidth":12,"monitoringDelayMilliseconds":80}"#.utf8
        )

        var layout = try JSONDecoder().decode(SpatialStageLayout.self, from: data)
        layout.migrateToCurrentVersion()

        #expect(layout.stageWidth == 12)
        #expect(layout.version == SpatialStageLayout.currentVersion)
        #expect(layout.monitoringDelayMilliseconds == 10)
        #expect(layout.excludedCreatureIDs.isEmpty)
    }

    @Test("new layouts use one RTP packet of monitoring delay")
    func newLayoutsUseOnePacketOfMonitoringDelay() {
        #expect(SpatialStageLayout().monitoringDelayMilliseconds == 10)
    }
}

@Suite("Spatial simulation playback")
struct SpatialSimulationPlaybackTests {
    @Test("non-looping playback publishes stopped at end of file")
    func nonLoopingPlaybackPublishesStoppedAtEndOfFile() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appendingPathExtension("wav")
        defer {
            try? FileManager.default.removeItem(at: fileURL)
        }
        try writeSimulationFile(to: fileURL)

        let (diagnostics, continuation) = AsyncStream<SpatialStageDiagnostics>.makeStream()
        let source = try SpatialSimulationAudioSource(
            renderer: ImmediateDrainSpatialRenderer(),
            fileURL: fileURL,
            channels: [3],
            onDiagnostics: { continuation.yield($0) }
        )

        source.start(looping: false)
        let finalState = await firstStoppedState(in: diagnostics)
        source.stop()
        continuation.finish()

        #expect(finalState == .stopped)
    }

    private func firstStoppedState(
        in diagnostics: AsyncStream<SpatialStageDiagnostics>
    ) async -> SpatialStageConnectionState? {
        await withTaskGroup(of: SpatialStageConnectionState?.self) { group in
            group.addTask {
                for await update in diagnostics {
                    if update.state == .stopped {
                        return update.state
                    }
                }
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(2))
                return nil
            }

            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }

    private func writeSimulationFile(to url: URL) throws {
        let channelCount: UInt16 = 17
        let bytesPerSample: UInt16 = 4
        let frameCount = Int(RTPAudioConstants.framesPerPacket)
        let blockAlignment = channelCount * bytesPerSample
        let dataSize = UInt32(frameCount * Int(blockAlignment))

        var data = Data("RIFF".utf8)
        appendLittleEndian(UInt32(36) + dataSize, to: &data)
        data.append(Data("WAVEfmt ".utf8))
        appendLittleEndian(UInt32(16), to: &data)
        appendLittleEndian(UInt16(3), to: &data)  // WAVE_FORMAT_IEEE_FLOAT
        appendLittleEndian(channelCount, to: &data)
        appendLittleEndian(RTPAudioConstants.sampleRate, to: &data)
        appendLittleEndian(
            RTPAudioConstants.sampleRate * UInt32(blockAlignment),
            to: &data
        )
        appendLittleEndian(blockAlignment, to: &data)
        appendLittleEndian(UInt16(32), to: &data)
        data.append(Data("data".utf8))
        appendLittleEndian(dataSize, to: &data)

        for _ in 0..<frameCount {
            for channel in 0..<Int(channelCount) {
                appendLittleEndian(
                    (channel == 2 ? Float(0.25) : Float.zero).bitPattern,
                    to: &data
                )
            }
        }
        try data.write(to: url)
    }

    private func appendLittleEndian<Value: FixedWidthInteger>(
        _ value: Value,
        to data: inout Data
    ) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) {
            data.append(contentsOf: $0)
        }
    }
}

private final class ImmediateDrainSpatialRenderer: SpatialSimulationAudioRendering,
    @unchecked Sendable
{
    var queuedFrames: Int { 0 }
    var outputPresentationLatency: TimeInterval { 0 }

    func reset(leadFrames _: Int, resumeAfterReset _: Bool) {}

    func enqueue(
        creatureSamples _: [Int: [Float]],
        backgroundSamples _: [Float],
        frameCount _: Int
    ) -> Bool {
        true
    }

    func pause() {}

    func resume() throws {}
}
