
import SwiftUI

struct AnimationDetail: View {
    
    var animationMetadata : AnimationMetadata
    
    
    var body: some View {
        ScrollView(.horizontal) {
            LazyHGrid(rows: Array(repeating: .init(.flexible()), count: 2), spacing: 16) {
                Text("Title: \(animationMetadata.title)")
                Text("Animation ID: \(animationMetadata.id)")
                Text("Number of Frames: \(animationMetadata.numberOfFrames)")
                Text("Milliseconds per Frame: \(animationMetadata.millisecondsPerFrame)")
                Text("Note: \(animationMetadata.note)")
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
    }
}

struct AnimationDetail_Preview: PreviewProvider {
    static var previews: some View {
        AnimationDetail(animationMetadata: .mock())
    }
}
