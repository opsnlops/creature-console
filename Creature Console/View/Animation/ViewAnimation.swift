//
//  ViewAnimation.swift
//  Creature Console
//
//  Created by April White on 4/20/23.
//

import SwiftUI

struct ViewAnimation: View {
    @EnvironmentObject var eventLoop : EventLoop

    private func processAnimationData(_ animation: Animation) -> ([UInt8], [UInt8], [UInt8], [UInt8], [UInt8], [UInt8]) {
            var axis0: [UInt8] = []
            var axis1: [UInt8] = []
            var axis2: [UInt8] = []
            var axis3: [UInt8] = []
            var axis4: [UInt8] = []
            var axis5: [UInt8] = []

            for i in 0..<animation.numberOfFrames {
                let f = animation.frames[Int(i)].motorBytes
                axis0.append(f[0])
                axis1.append(f[1])
                axis2.append(f[2])
                axis3.append(f[3])
                axis4.append(f[4])
                axis5.append(f[5])
            }

            return (axis0, axis1, axis2, axis3, axis4, axis5)
        }
    
    var body: some View {
        if let a = eventLoop.animation {
                let (axis0, axis1, axis2, axis3, axis4, axis5) = processAnimationData(a)
                VStack {
                    ByteChartView(data: axis0)
                    ByteChartView(data: axis1)
                    ByteChartView(data: axis2)
                    ByteChartView(data: axis3)
                    ByteChartView(data: axis4)
                    ByteChartView(data: axis5)
                }
            } else {
                Text("No Data")
            }
        }

}

struct ViewAnimation_Previews: PreviewProvider {
    static var previews: some View {
        ViewAnimation()
    }
}
