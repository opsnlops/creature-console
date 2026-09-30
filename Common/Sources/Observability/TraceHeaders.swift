import Instrumentation
import ServiceContextModule

/// The current trace as W3C header fields - `traceparent`, and `tracestate` when there is
/// one - for carrying it inside a message the next process picks up: the world's events carry
/// it, so a Bridge poll, the world's acceptance, and a mind's answer are one trace. Empty
/// outside a span.
public func currentTraceHeaders() -> [String: String] {
    guard let context = ServiceContext.current else { return [:] }
    var carrier: [String: String] = [:]
    InstrumentationSystem.instrument.inject(context, into: &carrier, using: HeaderInjector())
    return carrier
}

private struct HeaderInjector: Injector {
    typealias Carrier = [String: String]

    func inject(_ value: String, forKey key: String, into carrier: inout [String: String]) {
        carrier[key] = value
    }
}
