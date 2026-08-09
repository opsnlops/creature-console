#if os(tvOS)
    import SwiftUI

    struct TVSACNUniverseMonitorView: View {
        var body: some View {
            SACNUniverseMonitorView(layoutStyle: .fullScreen)
                .ignoresSafeArea()
                .hideBottomToolbar(true)
                // The full-screen grid is a pure display with no focusable controls — see
                // tvPassiveScreenEscape for why Menu would otherwise exit the whole app
                // (#72's one survivor).
                .tvPassiveScreenEscape()
        }
    }
#endif
