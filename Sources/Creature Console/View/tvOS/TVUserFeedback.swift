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
