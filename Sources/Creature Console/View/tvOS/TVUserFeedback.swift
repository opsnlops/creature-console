#if os(tvOS)
    import SwiftUI

    struct TVAlertDescriptor: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

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

    struct TVStatusToastView: View {
        let toast: TVStatusToast

        var body: some View {
            Text(toast.message)
                .font(.headline.weight(.semibold))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 30, style: .continuous)
                                .stroke(tintColor.opacity(0.7), lineWidth: 1.5)
                        )
                        .shadow(color: tintColor.opacity(0.5), radius: 18, y: 6)
                )
                .foregroundStyle(tintColor)
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
