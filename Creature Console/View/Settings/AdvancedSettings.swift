//
//  AdvancedSettings.swift
//  Creature Console
//
//  Created by April White on 4/17/23.
//

import Foundation
import SwiftUI


struct AdvancedSettingsView: View {
    @AppStorage("eventLoopMillisecondsPerFrame") private var eventLoopMillisecondsPerFrame: Int = 20
    @AppStorage("logSpareTimeFrameInterval") private var logSpareTimeFrameInterval: Int = 200
    @AppStorage("audioFilePath") private var audioFilePath: String = ""
    var body: some View {
        VStack {
            Text("⚠️ Changing any of these values requires an app restart")
                .padding()
            Form {
                Section(header: Text("Milliseconds Per Frame")) {
                    TextField("", value: $eventLoopMillisecondsPerFrame, format: .number)
                }
                Section(header: Text("Log Spare Time Frame Interval")) {
                    TextField("", value: $logSpareTimeFrameInterval, format: .number)
                }
                Section(header: Text("Audio File Path")) {
                    TextField("", text: $audioFilePath)
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
