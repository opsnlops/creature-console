//
//  AnimationDetail.swift
//  Creature Console
//
//  Created by April White on 5/4/23.
//

import SwiftUI

struct AnimationDetail: View {
    
    var animationMetadata : Animation.Metadata
    
    
    var body: some View {
        ScrollView(.horizontal) {
            LazyHGrid(rows: Array(repeating: .init(.flexible()), count: 2), spacing: 16) {
                Text("Title: \(animationMetadata.title)")
                Text("Number of Motors: \(animationMetadata.numberOfMotors)")
                Text("Number of Frames: \(animationMetadata.numberOfFrames)")
                Text("Milliseconds per Frame: \(animationMetadata.millisecondsPerFrame)")
                Text("Notes: \(animationMetadata.notes)")
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
