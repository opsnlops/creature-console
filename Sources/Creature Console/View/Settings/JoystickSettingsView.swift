import Common
import OSLog
import SwiftUI

struct JoystickSettingsView: View {
    @AppStorage("useOurJoystick") private var useOurJoystick: Bool = true
    @AppStorage("logJoystickPollEvents") var logJoystickPollEvents: Bool = false

    var body: some View {
        ZStack {
            LiquidGlass()
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "gamecontroller")
                        .font(.system(size: 16, weight: .semibold))
                        .padding(8)
                        .glassEffect(
                            .regular.tint(.accentColor).interactive(), in: .rect(cornerRadius: 8))
                    Text("Joystick Settings")
                        .font(.largeTitle.bold())
                }
                .padding(.bottom, 8)

                GlassEffectContainer(spacing: 24) {
                    // Card: Joystick Options
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Options", systemImage: "gamecontroller")
                            .font(.headline)
                        VStack(alignment: .leading, spacing: 8) {
                            #if os(macOS)
                                Toggle("Use our joystick if available", isOn: $useOurJoystick)
                            #endif
                            Toggle("Log joystick poll events", isOn: $logJoystickPollEvents)
                        }
                        .padding(12)
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(24)
        }
    }
}

struct JoystickSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        JoystickSettingsView()
    }
}
