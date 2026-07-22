// AdHocAssetsView.swift
// Shared formatting helper for the ad-hoc asset views (AdHocAnimationViews / AdHocSoundViews).

import Foundation

func adHocRelativeString(_ date: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .short
    return formatter.localizedString(for: date, relativeTo: Date())
}
