
import Common
import Foundation
import SwiftUI


struct BottomToolBarView: View {

    @ObservedObject var serverCounters = SystemCountersStore.shared

    var body: some View {


        HStack {
            Text("Server Frame: \(serverCounters.systemCounters.totalFrames)")
            Text("Rest Req: \(serverCounters.systemCounters.restRequestsProcessed)")
            Text("Streamed: \(serverCounters.systemCounters.framesStreamed)")
        }
        .padding()

    }
}

