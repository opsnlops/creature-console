#if os(tvOS)
    import SwiftUI

    struct TVStatusToast: Identifiable, Equatable {
        enum Kind {
            case success
            case error
            case info
        }

        let id = UUID()
        let kind: Kind
        let message: String
    }

    /// Escape hatch for *passive* pushed screens (the sACN grid, the joystick inspector —
    /// pure displays with no focusable controls). On tvOS, a pushed screen that focus never
    /// enters is a trap: Menu acts at the app root and EXITS THE APP instead of popping.
    /// This makes the screen itself the focus target and translates Menu into an explicit
    /// pop. Interactive screens don't need it — their controls take focus and Menu pops
    /// natively.
    private struct TVPassiveScreenEscape: ViewModifier {
        @Environment(\.dismiss) private var dismiss

        func body(content: Content) -> some View {
            content
                .focusable()
                .onExitCommand {
                    dismiss()
                }
        }
    }

    extension View {
        /// Apply to any pushed tvOS screen with no focusable controls, so Menu pops it
        /// instead of exiting the app.
        func tvPassiveScreenEscape() -> some View {
            modifier(TVPassiveScreenEscape())
        }
    }

    /// tvOS toast styled to match the StatusBanner convention: a tinted glass capsule
    /// floating over the content, with a green/red/blue tint keyed to the toast kind.
    struct TVStatusToastView: View {
        let toast: TVStatusToast

        var body: some View {
            Label(toast.message, systemImage: systemImage)
                .font(.headline.weight(.semibold))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
                .padding(.vertical, 16)
                .glassEffect(.regular.tint(tintColor.opacity(0.4)), in: .capsule)
        }

        private var systemImage: String {
            switch toast.kind {
            case .success:
                return "checkmark.circle.fill"
            case .error:
                return "exclamationmark.triangle.fill"
            case .info:
                return "info.circle.fill"
            }
        }

        private var tintColor: Color {
            switch toast.kind {
            case .success:
                return .green
            case .error:
                return .red
            case .info:
                return .blue
            }
        }
    }
#endif
