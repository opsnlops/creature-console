#if os(tvOS)
    import SwiftUI

    struct TVSACNUniverseMonitorView: View {
        var body: some View {
            SACNUniverseMonitorView(layoutStyle: .fullScreen)
                .ignoresSafeArea()
                .hideBottomToolbar(true)
        }
    }
#endif
