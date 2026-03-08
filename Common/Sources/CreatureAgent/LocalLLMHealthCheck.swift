import Foundation
import Logging
import Metrics
import ServiceLifecycle
import Tracing

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

struct LocalLLMHealthCheck: Service {
    private let healthURL: URL
    private let intervalSeconds: Int
    private let logger: Logger

    private let checkCounter: Counter
    private let failureCounter: Counter

    init(host: String, port: Int, intervalSeconds: Int, logger: Logger) {
        self.healthURL = URL(string: "http://\(host):\(port)/health")!
        self.intervalSeconds = intervalSeconds
        self.logger = logger
        self.checkCounter = Counter(label: "creature_agent.llm_health.checks")
        self.failureCounter = Counter(label: "creature_agent.llm_health.failures")
    }

    func run() async throws {
        logger.info(
            "Local LLM health check started (url: \(healthURL), interval: \(intervalSeconds)s)")

        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(intervalSeconds))
            } catch {
                break
            }
            await performCheck()
        }
    }

    private func performCheck() async {
        checkCounter.increment()

        do {
            try await withSpan("llm.health_check") { span in
                span.attributes["llm.health_url"] = healthURL.absoluteString

                let (data, response) = try await URLSession.shared.data(from: healthURL)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw HealthCheckError.invalidResponse
                }

                span.attributes["http.status_code"] = httpResponse.statusCode

                guard 200..<300 ~= httpResponse.statusCode else {
                    let body = String(data: data, encoding: .utf8) ?? ""
                    throw HealthCheckError.unhealthy(code: httpResponse.statusCode, body: body)
                }

                logger.debug("Local LLM health check passed")
            }
        } catch {
            failureCounter.increment()
            logger.error("Local LLM health check failed: \(error)")
        }
    }
}

enum HealthCheckError: Error, LocalizedError {
    case invalidResponse
    case unhealthy(code: Int, body: String)
    case connectionFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Local LLM health check received invalid response"
        case .unhealthy(let code, let body):
            if body.isEmpty {
                return "Local LLM health check returned status \(code)"
            }
            return "Local LLM health check returned status \(code): \(body)"
        case .connectionFailed(let error):
            return "Local LLM health check connection failed: \(error.localizedDescription)"
        }
    }
}
