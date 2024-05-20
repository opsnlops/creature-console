
import SwiftUI
import OSLog
import Common

struct InterfaceSettings: View {
    @AppStorage("serverLogsScrollBackLines") private var serverLogsScrollBackLines: Int = 0

    let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "InterfaceSettings")
    
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
            Form {
                Section(header: Text("Server Logs Scrollback Size")) {
                    Slider(value: intProxy, in: 10...200, step: 10.0)
                }
                Text("\(serverLogsScrollBackLines)")
            }
            Spacer()
        }

    }
    
    

}

struct InterfaceSettings_Previews: PreviewProvider {
    static var previews: some View {
        InterfaceSettings()
    }
}

