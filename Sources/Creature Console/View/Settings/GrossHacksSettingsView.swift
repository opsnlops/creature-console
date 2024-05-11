

import Foundation
import SwiftUI
import Common


struct GrossHacksSettingsView: View {
    @AppStorage("mfm2023PlaylistHack") private var mfm2023PlaylistHack: String = ""
    
    var body: some View {
        VStack {
            Text("🤮 These are a bunch of gross hacks for debugging 🤢")
                .padding()
            Form {
                Section(header: Text("MFM 2023 Playlist")) {
                    TextField("", text: $mfm2023PlaylistHack)
                        .disabled(false)
                }
            }
            Spacer()
        }
    }
}

struct GrossHacksSettingsView_Previews: PreviewProvider {
    static var previews: some View {
    GrossHacksSettingsView()
    }
}
