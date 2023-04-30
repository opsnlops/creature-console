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
    @EnvironmentObject var client: CreatureServerClient
    @State var animation : Animation?
    @State private var serverError: ServerError?
    
    let logger = Logger(label: "Record Animation")
    
    var body: some View {
        VStack {
            Text("Record New Animation")
                .padding()
            Button("Start Record") {
                
                let metadata = Animation.Metadata(title: "First!",
                                                  millisecondsPerFrame: Int32(eventLoop.millisecondPerFrame),
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
            Button("Save to Server") {
                Task {
                    if let a = eventLoop.animation {
                        let result = await client.createAnimation(animation: a)
                        switch(result) {
                        case .success(let horray):
                            logger.info("Server said: \(horray)")
                        case .failure(let shame):
                            serverError = shame
                        }
                    }
                }
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
        .alert(item: $serverError) { error in
            Alert(
                title: Text("Server Error"),
                message: Text(error.localizedDescription),
                dismissButton: .default(Text("OK"))
            )
        }
    }
}


struct RecordAnimation_Previews: PreviewProvider {
    static var previews: some View {
        RecordAnimation(joystick: .mock())
    }
}
