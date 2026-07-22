import Foundation

#if os(iOS) || os(visionOS)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

/// One place for "put this string on the clipboard" — replaces the identical
/// `#if os(...)` UIPasteboard/NSPasteboard blocks that were copy-pasted across seven views
/// (and lets those views drop their UIKit/AppKit imports entirely).
enum Pasteboard {
    @MainActor
    static func copy(_ string: String) {
        #if os(iOS) || os(visionOS)
            UIPasteboard.general.string = string
        #elseif canImport(AppKit)
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(string, forType: .string)
        #else
            // tvOS has no pasteboard; nothing to do.
        #endif
    }
}
