import MailKit

/// The Mail extension's entry point. Mail loads this for every message action it needs an
/// answer to; the answer is always "do nothing to the message" - the work is handing it over.
final class MailExtension: NSObject, MEExtension {
    func handlerForMessageActions() -> any MEMessageActionHandler {
        MailHandoff()
    }
}
