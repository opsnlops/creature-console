import Common
import Foundation
import SwiftUI

struct BottomToolBarView: View {

    @ObservedObject var eventLoop = EventLoop.shared
    @ObservedObject var serverCounters = SystemCountersStore.shared
    @ObservedObject var statusLights = StatusLightsManager.shared
    @StateObject var appState = AppState.shared


    var body: some View {


        HStack {
            VStack {
                HStack {
                    Text("Server Frame: \(serverCounters.systemCounters.totalFrames)")
                    Text("Rest Req: \(serverCounters.systemCounters.restRequestsProcessed)")
                    Text("Streamed: \(serverCounters.systemCounters.framesStreamed)")
                    Text("Spare Time: \(String(format: "%.2f", eventLoop.frameSpareTime))%")
                }
                HStack {
                    Text("State: \(appState.currentActivity)")
                        .font(.footnote)
                }
            }

            Spacer()

            Image(systemName: "arrow.circlepath")
                .foregroundColor(statusLights.running ? .accentColor : .primary)
                .font(.system(size: 24))
                .symbolRenderingMode(.multicolor)


            // Change up the streaming one to color vs not
            if statusLights.streaming {
                Image(systemName: "rainbow")

                    .font(.system(size: 24))
                    .symbolEffect(
                        .variableColor.cumulative.dimInactiveLayers.nonReversing,
                        isActive: statusLights.streaming
                    )
                    .symbolRenderingMode(.multicolor)
            } else {
                Image(systemName: "rainbow")
                    .foregroundColor(.primary)
                    .font(.system(size: 24))
            }


            if statusLights.dmx {
                Image(systemName: "antenna.radiowaves.left.and.right.circle.fill")
                    .foregroundColor(.accentColor)
                    .opacity(0.8)
                    .font(.system(size: 30))
                    .symbolEffect(
                        .variableColor.iterative.dimInactiveLayers.nonReversing,
                        isActive: statusLights.dmx
                    )
                    .symbolRenderingMode(.multicolor)
            } else {
                Image(systemName: "antenna.radiowaves.left.and.right.circle.fill")
                    .foregroundColor(.primary)
                    .font(.system(size: 30))
            }


            Image(systemName: "figure.socialdance")
                .foregroundColor(statusLights.animationPlaying ? .accentColor : .primary)
                .font(.system(size: 24))
                .symbolRenderingMode(.multicolor)


        }
        .padding()
        .alert(isPresented: $appState.showSystemAlert) {
            Alert(
                title: Text("Server Message"),
                message: Text("The server wants us to know: \(appState.systemAlertMessage)"),
                dismissButton: .default(Text("Okay 😅"))
            )
        }

    }
}
