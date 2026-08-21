// AdHocAssetsView.swift
// Shared formatting helper for the ad-hoc asset views
// (AdHocAnimationViews / AdHocSoundViews / AdHocExchangeViews).

import Foundation
import SwiftUI

/// A live "how long ago" label. `Text`'s relative date style keeps itself
/// current as time passes — a pre-formatted `String` freezes at whatever "now"
/// was at render time, and even a refresh won't thaw it because value-equal
/// rows never re-render.
func adHocRelativeText(_ date: Date) -> Text {
    Text(date, style: .relative) + Text(" ago")
}
