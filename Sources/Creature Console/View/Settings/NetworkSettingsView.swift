
import SwiftUI
import Common

struct NetworkSettingsView: View {
    @AppStorage("serverAddress") private var serverAddress: String = ""
    @AppStorage("serverPort") private var serverPort: Int = 0
    @AppStorage("activeUniverse") private var activeUniverse: Int = 1

    var body: some View {
        VStack {
            Form {
                Section(header: Text("Server Address")) {
                    TextField("", text: $serverAddress)
                }
                Section(header: Text("Server Port")) {
                    TextField("", value: $serverPort, format: .number)
                }
                Section(header: Text("Active Universe")) {
                    TextField("", value: $activeUniverse, format: .number)
                }
            }
            Spacer()
        }
    }
}

struct NetworkSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NetworkSettingsView()
    }
}
