import Common
import Foundation
import SwiftUI

struct AdvancedSettingsView: View {
    @AppStorage("eventLoopMillisecondsPerFrame") private var eventLoopMillisecondsPerFrame: Int = 20
    @AppStorage("logSpareTimeFrameInterval") private var logSpareTimeFrameInterval: Int = 200
    @AppStorage("updateSpareTimeStatusInterval") var updateSpareTimeStatusInterval: Int = 20
    @AppStorage("logSpareTime") private var logSpareTime: Bool = false

    var body: some View {
        VStack {
            Text("⚠️ Changing any of these values requires an app restart")
                .padding()
            Form {
                Section(header: Text("Milliseconds Per Frame")) {
                    TextField("", value: $eventLoopMillisecondsPerFrame, format: .number)
                }
                Section(header: Text("Log Spare Time?")) {
                    Toggle("Log Spare Time", isOn: $logSpareTime)
                }
                Section(header: Text("Log Spare Time Frame Interval")) {
                    TextField("", value: $logSpareTimeFrameInterval, format: .number)
                }
                Section(header: Text("Status Bar Spare Time Update Interval")) {
                    TextField("", value: $updateSpareTimeStatusInterval, format: .number)
                }
            }
            Spacer()
        }
    }
}

struct AdvancedSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        AdvancedSettingsView()
    }
}
