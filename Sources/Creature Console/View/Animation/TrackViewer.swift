import Common
import Foundation
import OSLog
import SwiftUI

struct TrackViewer: View {

    let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "TrackViewer")

    let track: Track
    let creature: Creature
    let inputs: [Input]
    var chartColor: Color = .accentColor

    var height: CGFloat = 50.0

    /// Dialog provenance for this creature's lane, when the animation was rendered from a dialog.
    /// Drives the mouth-activity ribbon + script panel; nil for hand-made animations.
    var lipsync: DialogProvenance.LipsyncTrack? = nil
    /// Word-level alignment for this lane (#56); nil for older renders (readout falls back to the
    /// mouth shape).
    var wordTrack: DialogProvenance.WordTrack? = nil
    var scriptLines: [DialogProvenance.ScriptLine] = []
    var millisecondsPerFrame: UInt32 = 20

    @State private var errorAlert: ErrorAlert?

    @State private var cachedStreams: [[UInt8]] = []
    @State private var cacheKey: String = ""

    enum TrackViewerError: LocalizedError {
        case inconsistentFrameSizes(expected: Int, found: Int)

        var errorDescription: String? {
            switch self {
            case .inconsistentFrameSizes(let expected, let found):
                return
                    "Inconsistent frame sizes detected. Expected size: \(expected), but found size: \(found)"
            }
        }
    }

    var body: some View {
        let result = extractByteStreams(from: track.frames)

        VStack {
            Text(creature.name)
            switch result {
            case .success:
                ForEach(0..<cachedStreams.count, id: \.self) { index in
                    HStack {
                        getInputView(for: index)
                            .frame(width: 80, alignment: .leading)
                            .padding()
                        ByteChartView(data: cachedStreams[index], color: chartColor)
                            .frame(height: height)
                    }
                }
                Text("Number of Frames: \(track.frames.count)")
                    .font(.footnote)

                if let lipsync {
                    TrackDialogSection(
                        lipsync: lipsync,
                        wordTrack: wordTrack,
                        scriptLines: scriptLines,
                        millisecondsPerFrame: millisecondsPerFrame,
                        frameCount: track.frames.count,
                        color: chartColor)
                }
            case .failure(let error):
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                    Text("Unable to display frame data")
                        .font(.headline)
                    Text(error.localizedDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }
        }
        .errorAlert($errorAlert, dismissLabel: "Oh no!")
        .task(id: makeCacheKey(frames: track.frames)) {
            // Validate data and show alert if needed
            let result = extractByteStreams(from: track.frames)
            if case .failure(let error) = result {
                errorAlert = ErrorAlert(
                    title: "Unable to Show Frame Data", message: error.localizedDescription)
            }

            // Update memoized cache
            if case .success(let streams) = result {
                cachedStreams = streams
            } else {
                cachedStreams = []
            }

            // Update our local cache key (optional bookkeeping)
            cacheKey = makeCacheKey(frames: track.frames)
        }
    }

    func extractByteStreams(from frames: [Data]) -> Result<[[UInt8]], TrackViewerError> {
        guard let firstFrame = frames.first else { return .success([]) }
        let frameSize = firstFrame.count

        // Ensure all frames have the same size
        for frame in frames {
            if frame.count != frameSize {
                let error: TrackViewerError = .inconsistentFrameSizes(
                    expected: frameSize, found: frame.count)
                logger.warning("\(error.localizedDescription, privacy: .public)")
                return .failure(error)
            }
        }

        // Initialize the byte streams array
        var byteStreams: [[UInt8]] = Array(repeating: [], count: frameSize)

        // Populate the byte streams
        for frame in frames {
            for (index, byte) in frame.enumerated() {
                byteStreams[index].append(byte)
            }
        }

        return .success(byteStreams)
    }

    @ViewBuilder
    func getInputView(for axis: Int) -> some View {
        if let input = inputs.first(where: { $0.joystickAxis == axis }) {
            VStack(alignment: .leading) {
                Text(formatInputName(input.name))
                Text("Axis: \(input.joystickAxis)")
                    .font(.caption)
                // Only show the Slot if it differs from the axis
                if input.slot != input.joystickAxis {
                    Text("Slot: \(input.slot)")
                        .font(.caption)
                }
                // Width is almost always 1, so don't show it unless it's weird
                if input.width != 1 {
                    Text("Width: \(input.width)")
                        .font(.caption)
                }
            }
        } else {
            Text("Axis \(axis)")
                .font(.headline)
        }
    }

    /// Make the format that's in the JSON more readable
    func formatInputName(_ name: String) -> String {
        return name.split(separator: "_")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    func makeCacheKey(frames: [Data]) -> String {
        let count = frames.count
        let width = frames.first?.count ?? 0
        var hasher = Hasher()
        hasher.combine(count)
        hasher.combine(width)
        // Incorporate frame contents to detect in-place updates (e.g., mouth data import)
        for frame in frames {
            hasher.combine(frame)
        }
        let contentHash = hasher.finalize()
        return "\(track.id.uuidString)-\(count)-\(width)-\(contentHash)"
    }
}


#Preview {
    TrackViewer(
        track: .mock(),
        creature: .mock(),
        inputs: [
            .mock(), .mock(), .mock(), .mock(),
            .mock(), .mock(), .mock(),
        ],
        chartColor: .orange  // Example color
    )
}
