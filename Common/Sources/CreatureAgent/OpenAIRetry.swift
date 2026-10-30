import AsyncHTTPClient
import Foundation
import Logging
import NIOCore

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// A request OpenAI could not take just then, sent again the way OpenAI's own SDKs do it: a 408,
/// 409, 429 or 5xx, or a connection that failed, after an exponential backoff with jitter, or
/// after the time the provider names in `retry-after-ms` or `retry-after`. Before #268 nothing
/// here was sent again. Mango's beliefs batch was looked at once a minute for 11 hours, and one
/// 503 from OpenAI's front door ended his night.
struct OpenAIRetry: Sendable {
    /// One request, answered: URLSession's call, or a test's.
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    static let urlSession: Transport = { try await URLSession.shared.data(for: $0) }

    /// Tries after the first.
    var retries: Int
    /// The first wait; each one after doubles, up to `longestWait`.
    var firstWait: Duration = .milliseconds(500)
    var longestWait: Duration = .seconds(8)
    /// A request that ran out of time is sent again only where nobody is waiting on it: a
    /// bird's reply that took a minute has missed its moment.
    var retriesTimeouts = false
    var sleep: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }

    /// A bird's reply: OpenAI's SDK default, two more tries within about two seconds.
    static let live = OpenAIRetry(retries: 2)
    /// The night's work: nobody is waiting, so eight more tries over about three minutes.
    static let night = OpenAIRetry(
        retries: 8, firstWait: .seconds(1), longestWait: .seconds(60), retriesTimeouts: true)

    /// What an answer says about sending again: its status, and how long the provider asked
    /// to be left.
    struct Answer: Sendable {
        var status: Int
        var retryAfter: Duration?
    }

    /// Sends until the answer is something other than "not now", or the tries are spent; the
    /// last answer, whatever it is, is the caller's to judge. `drop` lets go of an answer that
    /// will be sent again.
    func send<Response>(
        _ what: String, logger: Logger,
        answer: (Response) -> Answer,
        drop: (Response) async -> Void = { _ in },
        _ send: () async throws -> Response
    ) async throws -> Response {
        var resent = 0
        while true {
            let wait: Duration
            do {
                let response = try await send()
                let answer = answer(response)
                guard resent < retries, Self.isTransient(status: answer.status) else {
                    return response
                }
                await drop(response)
                wait = answer.retryAfter.map { min($0, longestWait) } ?? backoff(resent)
                logger.warning(
                    "OpenAI could not take the request; sending it again",
                    metadata: [
                        "openai.request": "\(what)",
                        "http.response.status_code": "\(answer.status)",
                        "http.request.resend_count": "\(resent + 1)", "retry.wait": "\(wait)",
                    ])
            } catch let error where resent < retries && isTransient(error) {
                wait = backoff(resent)
                logger.warning(
                    "The request to OpenAI failed on the way; sending it again",
                    metadata: [
                        "openai.request": "\(what)", "error": "\(error)",
                        "http.request.resend_count": "\(resent + 1)", "retry.wait": "\(wait)",
                    ])
            }
            resent += 1
            try await sleep(wait)
        }
    }

    /// One request through `transport`, sent again as above.
    func data(
        for request: URLRequest, _ what: String, logger: Logger,
        transport: Transport = OpenAIRetry.urlSession
    ) async throws -> (Data, URLResponse) {
        try await send(
            what, logger: logger,
            answer: { answered in
                guard let http = answered.1 as? HTTPURLResponse else { return Answer(status: 0) }
                return Answer(
                    status: http.statusCode,
                    retryAfter: Self.retryAfter(
                        ms: http.value(forHTTPHeaderField: "retry-after-ms"),
                        seconds: http.value(forHTTPHeaderField: "retry-after")))
            }
        ) { try await transport(request) }
    }

    // MARK: - What is worth sending again

    /// The statuses OpenAI's SDKs send again: a timeout (408), a conflict (409), too many
    /// requests (429), and the provider's own failures (5xx).
    static func isTransient(status: Int) -> Bool {
        status == 408 || status == 409 || status == 429 || status >= 500
    }

    /// A request that never reached OpenAI, lost its connection before the answer, or was
    /// answered with a status above - as this file's clients report it once the tries are
    /// spent.
    func isTransient(_ error: any Error) -> Bool {
        switch error {
        case OpenAIClientError.httpError(let code, _):
            return Self.isTransient(status: code)
        case let error as URLError:
            switch error.code {
            case .timedOut:
                return retriesTimeouts
            case .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed,
                .notConnectedToInternet, .secureConnectionFailed:
                return true
            default:
                return false
            }
        case let error as HTTPClientError:
            switch error {
            case .connectTimeout, .tlsHandshakeTimeout, .remoteConnectionClosed:
                return true
            case .readTimeout, .writeTimeout, .deadlineExceeded:
                return retriesTimeouts
            default:
                return false
            }
        case let error as IOError:
            return error.errnoCode == ECONNRESET || error.errnoCode == ECONNREFUSED
        default:
            return false
        }
    }

    /// How long the provider asked to be left: `retry-after-ms`, then `retry-after` in seconds,
    /// and nothing past a minute.
    static func retryAfter(ms: String?, seconds: String?) -> Duration? {
        if let ms, let value = Double(ms), value > 0, value <= 60_000 {
            return .milliseconds(value)
        }
        if let seconds, let value = Double(seconds), value > 0, value <= 60 {
            return .seconds(value)
        }
        return nil
    }

    /// The wait before the try after `resent`: doubled each time up to `longestWait`, and
    /// jittered down by up to a quarter so a flock of birds does not send again in step.
    func backoff(_ resent: Int) -> Duration {
        min(firstWait * (1 << min(resent, 16)), longestWait) * Double.random(in: 0.75...1)
    }
}
