import Common
import SwiftUI

struct AnimationWaveformEditor: View {

    var animation: Common.Animation?
    var creature: Creature
    var inputs: [Input] = [Input.mock()]

    var body: some View {
        if let a = animation {

            // Display each track
            VStack {
                Text(a.metadata.title)
                ForEach(a.tracks) { track in
                    HStack {
                        TrackViewer(
                            track: track,
                            creature: creature,
                            inputs: inputs
                        )
                    }
                }
            }
        }
    }


}

#Preview {
    AnimationWaveformEditor(
        animation: .mock(),
        creature: .mock()
    )
}
