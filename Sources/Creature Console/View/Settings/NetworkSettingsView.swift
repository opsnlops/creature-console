
import SwiftUI
import Common

struct NetworkSettingsView: View {
    @AppStorage("serverAddress") private var serverAddress: String = ""
    @AppStorage("serverPort") private var serverPort: Int = 0
    
    var body: some View {
        VStack {
            Form {
                Section(header: Text("Server Address")) {
                    TextField("", text: $serverAddress)
                }
                Section(header: Text("Server Port")) {
                    TextField("", value: $serverPort, format: .number)
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
