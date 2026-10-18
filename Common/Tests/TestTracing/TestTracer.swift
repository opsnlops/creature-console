import InMemoryTracing
import Tracing

/// The test process's one tracer. SwiftPM runs every test target in one process, and
/// bootstrapping twice is fatal, so every suite that reads spans, in any target, shares this one
/// and finds its own by what is on them (#249).
public let testTracer: InMemoryTracer = {
    let tracer = InMemoryTracer()
    InstrumentationSystem.bootstrap(tracer)
    return tracer
}()
