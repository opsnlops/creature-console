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

/// A trace carried inside a message - a world event's `traceparent` - as a context to continue
/// or to link to. Top level when the fields do not parse.
public func serviceContext(traceparent: String, tracestate: String? = nil) -> ServiceContext {
    var carrier = ["traceparent": traceparent]
    if let tracestate { carrier["tracestate"] = tracestate }
    var context = ServiceContext.topLevel
    InstrumentationSystem.instrument.extract(carrier, into: &context, using: HeaderExtractor())
    return context
}

/// The trace id in a W3C `traceparent` ("00-<trace id>-<span id>-<flags>"), nil when malformed.
public func traceID(ofTraceparent traceparent: String) -> Substring? {
    let parts = traceparent.split(separator: "-")
    return parts.count == 4 ? parts[1] : nil
}

private struct HeaderExtractor: Extractor {
    typealias Carrier = [String: String]

    func extract(key: String, from carrier: [String: String]) -> String? {
        carrier[key]
    }
}

private struct HeaderInjector: Injector {
    typealias Carrier = [String: String]

    func inject(_ value: String, forKey key: String, into carrier: inout [String: String]) {
        carrier[key] = value
    }
}
