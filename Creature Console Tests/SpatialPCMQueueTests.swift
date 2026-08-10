import Common
import Foundation
import Network
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

    @Test("a hardware render quantum can span two RTP packets without silence")
    func renderQuantumSpansPackets() {
        let queue = SpatialPCMQueue(capacity: 1_024)
        #expect(queue.write([Float](repeating: 1, count: 480)))
        #expect(queue.write([Float](repeating: 2, count: 480)))

        let output = read(512, from: queue)

        #expect(output.prefix(480).allSatisfy { $0 == 1 })
        #expect(output.suffix(32).allSatisfy { $0 == 2 })
        #expect(queue.availableFrames == 448)
        #expect(queue.underruns == 0)
    }

    @Test("reset clears prior underrun diagnostics")
    func resetClearsUnderrunDiagnostics() {
        let queue = SpatialPCMQueue(capacity: 8)
        _ = read(2, from: queue)
        #expect(queue.underruns == 1)

        queue.clearAndPrime(silenceFrames: 2)

        #expect(queue.underruns == 0)
    }

    @Test("capacity preflight matches subsequent writes")
    func capacityPreflightMatchesWrites() {
        let queue = SpatialPCMQueue(capacity: 5)
        #expect(queue.canWrite(frameCount: 5))
        #expect(queue.write([1, 2, 3]))
        #expect(queue.canWrite(frameCount: 2))
        #expect(!queue.canWrite(frameCount: 3))

        _ = read(2, from: queue)

        #expect(queue.canWrite(frameCount: 4))
        #expect(queue.write([4, 5, 6, 7]))
    }

    private func read(_ count: Int, from queue: SpatialPCMQueue) -> [Float] {
        var output = [Float](repeating: -1, count: count)
        output.withUnsafeMutableBufferPointer { buffer in
            _ = queue.read(into: buffer.baseAddress!, frameCount: count)
        }
        return output
    }
}

@Suite("Spatial RTCP scheduling")
struct SpatialRTCPSchedulingTests {
    @Test("playout delay accounts for outputs slower than the controller target")
    func accountsForOutputLatencyFloor() {
        #expect(
            abs(
                durationSeconds(
                    SpatialRTCPDelayPolicy.effectivePlayoutDelay(
                        configured: .milliseconds(20),
                        outputLatency: 0.014
                    )
                ) - 0.024
            ) < 0.000_001
        )
        #expect(
            abs(
                durationSeconds(
                    SpatialRTCPDelayPolicy.effectivePlayoutDelay(
                        configured: .milliseconds(20),
                        outputLatency: 0.100
                    )
                ) - 0.110
            ) < 0.000_001
        )
    }

    @Test("pre-roll converts a future enqueue deadline to exact audio frames")
    func convertsDeadlineToPrerollFrames() {
        let now = ContinuousClock.now

        #expect(
            SpatialRTCPPreroll.frameCount(
                until: now.advanced(by: .milliseconds(6)),
                now: now
            ) == 288
        )
        #expect(
            SpatialRTCPPreroll.frameCount(
                until: now.advanced(by: .milliseconds(-1)),
                now: now
            ) == 0
        )
    }

    @Test("validation requires a fresh report for every active creature")
    func requiresCompleteFreshReportSet() {
        let now = ContinuousClock.now
        let background = timedReport(source: 17, receivedAt: now)
        let creature = timedReport(source: 1, receivedAt: now)

        #expect(
            SpatialRTCPReportValidation.reportsAreCompatible(
                background: background,
                creatures: [creature],
                expectedCreatureCount: 1,
                now: now
            )
        )
        #expect(
            !SpatialRTCPReportValidation.reportsAreCompatible(
                background: background,
                creatures: [creature],
                expectedCreatureCount: 2,
                now: now
            )
        )
        #expect(
            !SpatialRTCPReportValidation.reportsAreCompatible(
                background: background,
                creatures: [
                    timedReport(
                        source: 1,
                        receivedAt: now.advanced(by: .milliseconds(-2_501))
                    )
                ],
                expectedCreatureCount: 1,
                now: now
            )
        )
    }

    @Test("validation rejects reports from a different clock")
    func rejectsIncompatibleClockMapping() {
        let now = ContinuousClock.now
        let background = timedReport(source: 17, receivedAt: now)
        let creature = timedReport(
            source: 1,
            canonicalName: "another-server",
            receivedAt: now
        )

        #expect(
            !SpatialRTCPReportValidation.reportsAreCompatible(
                background: background,
                creatures: [creature],
                expectedCreatureCount: 1,
                now: now
            )
        )
    }

    private func timedReport(
        source: UInt32,
        canonicalName: String = "creature-server@test",
        receivedAt: ContinuousClock.Instant
    ) -> TimedRTCPSenderReport {
        TimedRTCPSenderReport(
            report: RTCPSenderReport(
                synchronizationSource: source,
                ntpTimestamp: UInt64(2_208_988_800) << 32,
                rtpTimestamp: 10_000,
                packetCount: 1,
                octetCount: 1,
                canonicalName: canonicalName
            ),
            receivedAt: receivedAt
        )
    }

    private func durationSeconds(_ duration: Duration) -> TimeInterval {
        let components = duration.components
        return Double(components.seconds)
            + Double(components.attoseconds) / 1_000_000_000_000_000_000
    }
}

@Suite("Spatial live buffering")
struct SpatialLiveBufferPolicyTests {
    @Test("queue target covers a hardware render quantum and one RTP packet")
    func targetCoversRenderQuantum() {
        let target = SpatialLiveBufferPolicy.targetQueuedFrames(
            requestedDelayFrames: 480,
            renderQuantumFrames: 512
        )

        #expect(target == 992)
    }

    @Test("a larger requested delay remains authoritative")
    func preservesLargerRequestedDelay() {
        let target = SpatialLiveBufferPolicy.targetQueuedFrames(
            requestedDelayFrames: 3_840,
            renderQuantumFrames: 512
        )

        #expect(target == 3_840)
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

@Suite("Spatial multicast receiver")
struct SpatialMulticastReceiverTests {
    @Test("combines selected channels and BGM into one subscription set per port")
    func buildsSubscriptionsForOneListener() {
        let subscriptions = SpatialMulticastReceiver.subscriptions(
            channels: [3, 1, 3, 0, 18],
            port: RTPAudioConstants.rtpPort
        )

        #expect(subscriptions.map(\.channel) == [1, 3, 17])
        #expect(Set(subscriptions.map(\.endpoint)).count == 3)
        #expect(
            subscriptions.map(\.endpoint) == [
                multicastEndpoint(address: "239.19.63.1", port: 5004),
                multicastEndpoint(address: "239.19.63.3", port: 5004),
                multicastEndpoint(address: "239.19.63.17", port: 5004),
            ]
        )
    }

    @Test("RTP and RTCP subscription sets use their respective ports")
    func usesProtocolPortForEveryEndpoint() {
        let rtp = SpatialMulticastReceiver.subscriptions(channels: [4], port: 5004)
        let rtcp = SpatialMulticastReceiver.subscriptions(channels: [4], port: 5005)

        #expect(rtp.map(\.channel) == rtcp.map(\.channel))
        #expect(rtp.map(\.endpoint) != rtcp.map(\.endpoint))
        #expect(
            rtcp.map(\.endpoint) == [
                multicastEndpoint(address: "239.19.63.4", port: 5005),
                multicastEndpoint(address: "239.19.63.17", port: 5005),
            ]
        )
    }

    private func multicastEndpoint(address: String, port: UInt16) -> NWEndpoint {
        .hostPort(
            host: NWEndpoint.Host(address),
            port: NWEndpoint.Port(rawValue: port)!
        )
    }
}

@Suite("Spatial stage migration")
struct SpatialStageMigrationTests {
    @Test("v1 monitoring delay sentinel migrates to one RTP packet")
    func legacyMonitoringDelayMigratesToOnePacket() throws {
        let data = Data(
            #"{"version":1,"stageWidth":12,"monitoringDelayMilliseconds":80}"#.utf8
        )

        let layout = try JSONDecoder().decode(LegacySpatialStageLayout.self, from: data)

        #expect(layout.monitoringDelayMilliseconds == 10)
        #expect(layout.commonPlayoutDelayMilliseconds == 20)
        #expect(layout.placements.isEmpty)
    }

    @Test("legacy layout converts into the server stage model")
    func legacyLayoutConvertsToServerStage() throws {
        let data = Data(
            """
            {
              "version": 3,
              "listenerX": 0,
              "listenerY": 1.6,
              "listenerZ": 2,
              "listenerYaw": 0,
              "monitoringDelayMilliseconds": 20,
              "commonPlayoutDelayMilliseconds": 30,
              "backgroundMusicGain": 0.5,
              "reverbBlend": 0.1,
              "placements": [
                {
                  "creatureID": "one",
                  "creatureName": "One",
                  "audioChannel": 3,
                  "x": 1,
                  "y": 1.4,
                  "z": -2,
                  "gain": 0.8,
                  "isMuted": true
                }
              ]
            }
            """.utf8
        )

        let legacy = try JSONDecoder().decode(LegacySpatialStageLayout.self, from: data)
        let stage = SpatialStageMigration.stage(from: legacy, title: "Migrated")
        let placement = try #require(stage.placements.first)

        #expect(stage.title == "Migrated")
        #expect(stage.version == StageLimits.currentVersion)
        #expect(placement.creatureID == "one")
        #expect(placement.audioChannel == 3)
        #expect(placement.x == 1)
        #expect(abs(placement.y - (-0.2)) < 0.0001)
        #expect(placement.z == -4)
        #expect(placement.gain == 0.8)
        #expect(placement.isMuted)
        #expect(stage.audio.monitoringDelayMilliseconds == 20)
        #expect(stage.audio.commonPlayoutDelayMilliseconds == 30)
        #expect(stage.audio.backgroundMusicGain == 0.5)
        #expect(stage.audio.reverbBlend == 0.1)
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

    func reset(leadFrames _: Int, resumeAfterReset _: Bool) throws {}

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
