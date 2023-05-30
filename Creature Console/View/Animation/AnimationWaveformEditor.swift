//
//  AnimationWaveformEditor.swift
//  Creature Console
//
//  Created by April White on 5/14/23.
//

import SwiftUI

struct AnimationWaveformEditor: View {
    
    @Binding var animation : Animation?
    @Binding var creature : Creature
    
    var body: some View {
        if let a = animation {
            let allAxes = processAnimationData(a)
            VStack {
                //Text(animation.metadata.title)
                ForEach(allAxes.indices, id: \.self) { i in
                    HStack {
                        Text(creature.motors[i].name)
                            .frame(width: 100)
                        ByteChartView(data: allAxes[i])
                    }
                }
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

struct AnimationWaveformEditor_Previews: PreviewProvider {
    static var previews: some View {
        AnimationWaveformEditor(animation: .constant(.mock()),
                                creature: .constant(.mock()))
    }
}
