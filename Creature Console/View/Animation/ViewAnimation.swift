//
//  ViewAnimation.swift
//  Creature Console
//
//  Created by April White on 4/20/23.
//

import SwiftUI

struct ViewAnimation: View {
    @State var animation : Animation

    init(animation: Animation) {
        self.animation = animation
    }
    
    var body: some View {
        let allAxes = processAnimationData(animation)
        VStack {
            //Text(animation.metadata.title)
            ForEach(allAxes.indices, id: \.self) { i in
                ByteChartView(data: allAxes[i])
            }
        }
    }
    
    private func processAnimationData(_ animation: Animation) -> [[UInt8]] {
        var allAxes: [[UInt8]] = Array(repeating: [], count: Int(animation.metadata.numberOfMotors))

        for i in 0..<animation.numberOfFrames {
            let f = animation.frames[Int(i)].motorBytes
            for j in 0..<Int(animation.metadata.numberOfMotors) {
                allAxes[j].append(f[j])
            }
        }

        return allAxes
    }
}

struct ViewAnimation_Previews: PreviewProvider {
    static var previews: some View {
        ViewAnimation(animation: .mock())
    }
}
