import Common
import Foundation
import OSLog
import SwiftUI

struct TrackViewer: View {

    let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "TrackViewer")

    @State var track: Track
    @State var creature: Creature
    @State var inputs: [Input]
    var chartColor: Color = .accentColor

    var height: CGFloat = 70.0

    @State private var showErrorAlert = false
    @State private var alertMessage = ""

    var body: some View {
        let byteStreams = extractByteStreams(from: track.frames)

        VStack {
            Text(creature.name)
            ForEach(0..<byteStreams.count, id: \.self) { index in
                HStack {
                    getInputView(for: index)
                        .frame(width: 80, alignment: .leading)
                        .padding()
                    ByteChartView(data: byteStreams[index], color: chartColor)
                        .frame(height: height)
                }
            }
        }
        .alert(isPresented: $showErrorAlert) {
            Alert(
                title: Text("Unable to Show Frame Data"),
                message: Text(alertMessage),
                dismissButton: .default(Text("Oh no!"))
            )
        }
    }

    func extractByteStreams(from frames: [Data]) -> [[UInt8]] {
        guard let firstFrame = frames.first else { return [] }
        let frameSize = firstFrame.count

        // Ensure all frames have the same size
        for frame in frames {
            if frame.count != frameSize {
                alertMessage = String(
                    "Inconsistent frame sizes detected. Expected size: \(frameSize), but found size: \(frame.count)"
                )
                logger.warning("\(alertMessage, privacy: .public)")
                showErrorAlert = true
                return []
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

        return byteStreams
    }

    func getInputView(for axis: Int) -> AnyView {
        if let input = inputs.first(where: { $0.joystickAxis == axis }) {
            return AnyView(
                VStack(alignment: .leading) {
                    Text(formatInputName(input.name))
                        .font(.headline)
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
            )
        } else {
            return AnyView(
                Text("Axis \(axis)")
                    .font(.headline)
            )
        }
    }

    /// Make the format that's in the JSON more readable
    func formatInputName(_ name: String) -> String {
        return name.split(separator: "_")
            .map { $0.capitalized }
            .joined(separator: " ")
    }
}

struct TrackViewer_Previews: PreviewProvider {
    static var previews: some View {
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
}
