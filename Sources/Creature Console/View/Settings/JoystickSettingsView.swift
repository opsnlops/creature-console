import Common
import OSLog
import SwiftUI

struct JoystickSettingsView: View {
    @AppStorage("useOurJoystick") private var useOurJoystick: Bool = true
    @AppStorage("logJoystickPollEvents") var logJoystickPollEvents: Bool = false

    var body: some View {
        VStack {
            Spacer()
            #if os(macOS)
                Form {
                    Toggle("Use our joystick if available", isOn: $useOurJoystick)
                }
            #endif
            Form {
                Toggle("Log joystick poll events", isOn: $logJoystickPollEvents)
            }
            Spacer()
        }
    }
}

struct JoystickSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        JoystickSettingsView()
    }
}
