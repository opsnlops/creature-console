//
//  UISettings.swift
//  Creature Console
//
//  Created by April White on 4/15/23.
//

import SwiftUI

struct InterfaceSettings: View {
    @AppStorage("serverLogsScrollBackLines") private var serverLogsScrollBackLines: Int = 0
    
    var intProxy: Binding<Double>{
            Binding<Double>(get: {
            
                return Double(serverLogsScrollBackLines)
                
            }, set: {
                // rounds the double to an Int
                serverLogsScrollBackLines = Int($0)
            })
        }
    
    var body: some View {
        VStack {
            Spacer()
            Form {
                Section(header: Text("Server Logs Scrollback Size")) {
                    Slider(value: intProxy, in: 10...200, step: 10.0)
                }
                Text("\(serverLogsScrollBackLines)")
                    
            }
        }
    }
}

struct InterfaceSettings_Previews: PreviewProvider {
    static var previews: some View {
        InterfaceSettings()
    }
}

