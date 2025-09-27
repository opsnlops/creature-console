import Foundation

#if canImport(MessageUI) && os(iOS)
    import MessageUI
    import UIKit

    @MainActor
    public final class MailComposer: NSObject {
        public static func present(
            subject: String, body: String, to: [String] = [], attachments: [URL] = []
        ) {
            if MFMailComposeViewController.canSendMail() {
                let vc = MFMailComposeViewController()
                vc.setSubject(subject)
                vc.setMessageBody(body, isHTML: false)
                if !to.isEmpty { vc.setToRecipients(to) }
                for url in attachments {
                    if let data = try? Data(contentsOf: url) {
                        vc.addAttachmentData(
                            data, mimeType: "application/json", fileName: url.lastPathComponent)
                    }
                }
                let presenter = topViewController()
                vc.mailComposeDelegate = shared
                presenter?.present(vc, animated: true)
            } else {
                // Fallback to mailto URL
                openMailto(subject: subject, body: body, to: to.first)
            }
        }

        private static let shared = MailComposer()

        private static func topViewController(
            base: UIViewController? = UIApplication.shared.connectedScenes.compactMap {
                ($0 as? UIWindowScene)?.keyWindow
            }.first?.rootViewController
        ) -> UIViewController? {
            if let nav = base as? UINavigationController {
                return topViewController(base: nav.visibleViewController)
            }
            if let tab = base as? UITabBarController, let selected = tab.selectedViewController {
                return topViewController(base: selected)
            }
            if let presented = base?.presentedViewController {
                return topViewController(base: presented)
            }
            return base
        }

        private static func openMailto(subject: String, body: String, to: String?) {
            let encodedSubject =
                subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? subject
            let encodedBody =
                body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? body
            let recipient = to ?? ""
            if let url = URL(
                string: "mailto:\(recipient)?subject=\(encodedSubject)&body=\(encodedBody)")
            {
                UIApplication.shared.open(url)
            }
        }
    }

    extension MailComposer: MFMailComposeViewControllerDelegate {
        nonisolated public func mailComposeController(
            _ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            Task { @MainActor in
                controller.dismiss(animated: true)
            }
        }
    }

#else

    #if os(macOS)
        import AppKit
    #endif

    #if canImport(UIKit)
        import UIKit
    #endif

    @MainActor
    public final class MailComposer {
        public static func present(
            subject: String, body: String, to: [String] = [], attachments: [URL] = []
        ) {
            let encodedSubject =
                subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? subject
            let encodedBody =
                body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? body
            let recipient = to.first ?? ""
            if let url = URL(
                string: "mailto:\(recipient)?subject=\(encodedSubject)&body=\(encodedBody)")
            {
                #if os(macOS)
                    NSWorkspace.shared.open(url)
                #else
                    #if canImport(UIKit)
                        UIApplication.shared.open(url)
                    #else
                        // No-op: cannot open mailto on this platform
                    #endif
                #endif
            }
        }
    }

#endif
