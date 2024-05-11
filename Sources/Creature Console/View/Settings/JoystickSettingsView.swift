import SwiftUI
import OSLog
import Common

struct JoystickSettingsView: View {
    @AppStorage("useOurJoystick") private var useOurJoystick: Bool = true
    
    var body: some View {
        VStack {
            Spacer()
            Form {
                Toggle("Use our joystick if available", isOn: $useOurJoystick)
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

