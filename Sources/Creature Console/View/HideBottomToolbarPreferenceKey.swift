import SwiftUI

struct HideBottomToolbarPreferenceKey: PreferenceKey {
    static let defaultValue: Bool = false

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

extension View {
    func hideBottomToolbar(_ hide: Bool) -> some View {
        preference(key: HideBottomToolbarPreferenceKey.self, value: hide)
    }
}
