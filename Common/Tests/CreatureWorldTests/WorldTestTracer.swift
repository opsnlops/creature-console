import InMemoryTracing
import Tracing

/// The test process's one tracer: bootstrapping twice is fatal, so every suite that reads
/// spans shares this one and finds its own by what is on them.
let worldTestTracer: InMemoryTracer = {
    let tracer = InMemoryTracer()
    InstrumentationSystem.bootstrap(tracer)
    return tracer
}()
