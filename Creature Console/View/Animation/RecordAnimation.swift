//
//  RecordAnimation.swift
//  Creature Console
//
//  Created by April White on 4/20/23.
//

import SwiftUI
import Logging

struct RecordAnimation: View {
    @ObservedObject var joystick : SixAxisJoystick
    @EnvironmentObject var eventLoop : EventLoop
    @State var animation : Animation?
    
    let logger = Logger(label: "Record Animation")
    
    var body: some View {
        VStack {
            Text("Record New Animation")
                .padding()
            Button("Start Record") {
                
                let metadata = Animation.Metadata(title: "First!",
                                                  framesPerSecond: Int32(UserDefaults.standard.double(forKey: "eventLoopFramesPerSecond")),
                                                  creatureType: .wledLight,
                                                  numberOfMotors: 6,
                                                  notes: "Please work!")
                
                logger.info("asking new recording to start")
                eventLoop.recordNewAnimation(metadata: metadata)
                
            }
            .padding()
            Button("Stop Recording") {
                eventLoop.stopRecording()
                logger.info("asked recording to stop")
                
                // Point our stuff at it
                animation = eventLoop.animation
            }
            .padding()
            HStack {
                Text("Frames: \(animation?.numberOfFrames ?? -1)")
                Text("Notes: \(animation?.metadata.notes ?? "--")")
            }
        }
        .onDisappear{
            self.joystick.removeVirtualJoystickIfNeeded()
        }
        .onAppear {
            self.joystick.showVirtualJoystickIfNeeded()
        }
    }
}


