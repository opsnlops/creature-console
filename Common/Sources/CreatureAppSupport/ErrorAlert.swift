import Common
import SwiftUI

public struct ErrorAlert: Identifiable {
    public let id = UUID()
    public var title: String
    public var message: String

    public init(title: String = "Error", message: String) {
        self.title = title
        self.message = message
    }

    public init(title: String = "Error", error: any Error) {
        self.init(title: title, message: ServerError.detailedMessage(from: error))
    }
}

extension View {
    public func errorAlert(
        _ error: Binding<ErrorAlert?>,
        dismissLabel: String = "OK",
        onDismiss: @escaping () -> Void = {}
    ) -> some View {
        alert(
            error.wrappedValue?.title ?? "Error",
            isPresented: Binding(
                get: { error.wrappedValue != nil },
                set: { presented in if !presented { error.wrappedValue = nil } }
            ),
            presenting: error.wrappedValue
        ) { _ in
            Button(dismissLabel, role: .cancel) { onDismiss() }
        } message: { alert in
            Text(alert.message)
        }
    }
}
