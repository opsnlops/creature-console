import Common
import SwiftUI

struct NetworkSettingsView: View {
    @AppStorage("serverAddress") private var serverAddress: String = ""
    @AppStorage("serverPort") private var serverPort: Int = 0
    @AppStorage("serverUseTLS") private var serverUseTLS: Bool = true
    @AppStorage("activeUniverse") private var activeUniverse: Int = 1


    var body: some View {
        VStack {
            Form {

                Section(header: Text("Server Connection")) {
                    TextField("Address", text: $serverAddress)
                    TextField("Port", value: $serverPort, format: .number)
                    Toggle("Use TLS", isOn: $serverUseTLS)
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
