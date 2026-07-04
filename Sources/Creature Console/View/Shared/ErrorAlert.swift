import Common
import SwiftUI

/// A presentable error alert — an optional title plus a message — backing the shared
/// `.errorAlert(_:)` modifier.
///
/// This replaces the per-view `showError` / `errorMessage` / `presentError(...)` triads
/// that were copy-pasted across ~two dozen views, along with the tvOS `TVAlertDescriptor`
/// value type (issue #8). Build one from a thrown
/// error and it preserves the server's detailed message automatically:
///
/// ```swift
/// @State private var errorAlert: ErrorAlert?
/// // ...
/// .errorAlert($errorAlert)
/// // ...
/// errorAlert = ErrorAlert(title: "Render Error", error: error)
/// ```
struct ErrorAlert: Identifiable {
    let id = UUID()
    var title: String
    var message: String

    init(title: String = "Error", message: String) {
        self.title = title
        self.message = message
    }

    /// Build from any thrown error, preserving the server's detailed message rather than
    /// the lossy `localizedDescription`.
    init(title: String = "Error", error: any Error) {
        self.init(title: title, message: ServerError.detailedMessage(from: error))
    }
}

extension View {
    /// Presents `error` as a single-button ("OK") alert whenever it becomes non-nil,
    /// clearing it back to `nil` on dismiss. Uses the modern
    /// `alert(_:isPresented:presenting:)` API rather than the deprecated `Alert` type.
    ///
    /// - Parameter onDismiss: optional side effect to run when the alert is dismissed
    ///   (e.g. resetting a trigger binding so the same action can fire again).
    func errorAlert(_ error: Binding<ErrorAlert?>, onDismiss: @escaping () -> Void = {})
        -> some View
    {
        alert(
            error.wrappedValue?.title ?? "Error",
            isPresented: Binding(
                get: { error.wrappedValue != nil },
                set: { presented in if !presented { error.wrappedValue = nil } }
            ),
            presenting: error.wrappedValue
        ) { _ in
            Button("OK", role: .cancel) { onDismiss() }
        } message: { alert in
            Text(alert.message)
        }
    }
}
