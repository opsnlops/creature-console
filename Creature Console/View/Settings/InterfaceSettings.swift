
import SwiftUI
import OSLog

struct InterfaceSettings: View {
    @AppStorage("serverLogsScrollBackLines") private var serverLogsScrollBackLines: Int = 0
    
    @State private var channelCustomNames: [Int: String] = [:]
    @AppStorage("channelCustomNames") private var channelCustomNamesData: Data?
    
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
                
                // Editable section for Channel Custom Names
                if !channelCustomNames.isEmpty {
                    Section(header: Text("Channel Custom Names")) {
                        ForEach(Array(channelCustomNames.keys).sorted(), id: \.self) { key in
                            TextField("Channel \(key)", text: Binding(
                                get: { self.channelCustomNames[key, default: ""] },
                                set: { newValue in
                                    self.channelCustomNames[key] = newValue
                                    saveChannelCustomNames()
                                }
                            ))
                        }
                    }
                }
                    
            }
            Spacer()
        }
        .onAppear {
            loadChannelCustomNames()
        }
    }
    
    
    private func loadChannelCustomNames() {
        // Deserialize `channelCustomNamesData` to `channelCustomNames`
        if let data = channelCustomNamesData {
            do {
                channelCustomNames = try NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data) as? [Int: String] ?? [:]
            } catch {
                logger.error("Failed to load or decode channel custom names")
            }
        }
    }
    
    private func saveChannelCustomNames() {
        // Serialize `channelCustomNames` and save it to `channelCustomNamesData`
        do {
            let data = try NSKeyedArchiver.archivedData(withRootObject: channelCustomNames, requiringSecureCoding: false)
            channelCustomNamesData = data
        } catch {
            logger.error("Failed to encode or save channel custom names")
        }
    }
}

struct InterfaceSettings_Previews: PreviewProvider {
    static var previews: some View {
        InterfaceSettings()
    }
}

