#if canImport(SwiftUI)
    import SwiftUI

    /// SwiftUI helper for binding directly to the shared resume-playlist preference.
    @propertyWrapper
    @MainActor
    public struct PlaylistResumePreference: DynamicProperty {
        @ObservedObject private var store: PlaylistRuntimeStore = .shared

        public init() {}

        public var wrappedValue: Bool {
            get { store.resumePlaylistAfterPlayback }
            nonmutating set { store.resumePlaylistAfterPlayback = newValue }
        }

        public var projectedValue: Binding<Bool> {
            Binding(
                get: { store.resumePlaylistAfterPlayback },
                set: { store.resumePlaylistAfterPlayback = $0 }
            )
        }
    }
#endif
