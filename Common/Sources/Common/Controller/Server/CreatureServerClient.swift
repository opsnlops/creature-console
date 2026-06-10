import Foundation
import Logging
import Tracing

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

public final class CreatureServerClient: CreatureServerClientProtocol, Sendable {

    public static let shared = CreatureServerClient()
    typealias HTTPDataLoader = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    struct HTTPResponseData: Sendable {
        let data: Data
        let statusCode: Int
        let contentDisposition: String?
    }

    // WebSocket processing stuff
    private let _processor: CreatureLock<MessageProcessor?>

    var processor: MessageProcessor? {
        get { _processor.withLock { $0 } }
        set { _processor.withLock { $0 = newValue } }
    }

    private let _webSocketClient: CreatureLock<WebSocketClient?>

    var webSocketClient: WebSocketClient? {
        get { _webSocketClient.withLock { $0 } }
        set { _webSocketClient.withLock { $0 = newValue } }
    }

    let logger: Logging.Logger
    private let httpDataLoader: HTTPDataLoader
    private let _serverHostname: CreatureLock<String>
    private let _serverPort: CreatureLock<Int>
    private let _useTLS: CreatureLock<Bool>
    private let _serverProxyHost: CreatureLock<String?>
    private let _apiKey: CreatureLock<String?>

    public var serverHostname: String {
        get { _serverHostname.withLock { $0 } }
        set { _serverHostname.withLock { $0 = newValue } }
    }

    public var serverPort: Int {
        get { _serverPort.withLock { $0 } }
        set { _serverPort.withLock { $0 = newValue } }
    }

    public var useTLS: Bool {
        get { _useTLS.withLock { $0 } }
        set { _useTLS.withLock { $0 = newValue } }
    }

    public var serverProxyHost: String? {
        get { _serverProxyHost.withLock { $0 } }
        set { _serverProxyHost.withLock { $0 = newValue } }
    }

    public var apiKey: String? {
        get { _apiKey.withLock { $0 } }
        set { _apiKey.withLock { $0 = newValue } }
    }


    public enum UrlType {
        case http
        case websocket
    }


    public convenience init() {
        self.init { request in
            try await URLSession.shared.data(for: request)
        }
    }

    init(httpDataLoader: @escaping HTTPDataLoader) {
        var logger = Logging.Logger(label: "io.opsnlops.creature-controller.common")
        logger.logLevel = .debug
        self.logger = logger
        self.httpDataLoader = httpDataLoader
        self._processor = CreatureLock(initialState: nil)
        self._webSocketClient = CreatureLock(initialState: nil)
        self._serverHostname = CreatureLock(
            initialState: UserDefaults.standard.string(forKey: "serverAddress") ?? "127.0.0.1")
        self._serverPort = CreatureLock(
            initialState: UserDefaults.standard.integer(forKey: "serverPort"))
        self._useTLS = CreatureLock(
            initialState: UserDefaults.standard.object(forKey: "serverUseTLS") as? Bool ?? true)
        self._serverProxyHost = CreatureLock(
            initialState: UserDefaults.standard.string(forKey: "serverProxyHost"))
        self._apiKey = CreatureLock(initialState: nil)
        self.logger.info("Created new CreatureServerRestful")
    }

    /**
     Returns the URL to our server
    
     @param type Which type of URL to make (http or websocket)
     */
    public func makeBaseURL(_ type: UrlType) -> String {

        var prefix: String
        switch type {
        case (.http):
            prefix = useTLS ? "https://" : "http://"
        case (.websocket):
            prefix = useTLS ? "wss://" : "ws://"
        }

        // Use proxy host if both proxyHost and apiKey are configured
        let host: String
        if let proxy = serverProxyHost, apiKey != nil {
            host = proxy
        } else {
            host = "\(serverHostname):\(serverPort)"
        }

        return "\(prefix)\(host)/api/v1"
    }

    public func connect(
        serverHostname: String, serverPort: Int, useTLS: Bool, serverProxyHost: String? = nil,
        apiKey: String? = nil
    ) throws {
        self.serverHostname = serverHostname
        self.serverPort = serverPort
        self.useTLS = useTLS
        self.serverProxyHost = serverProxyHost
        self.apiKey = apiKey

        if let proxy = serverProxyHost, apiKey != nil {
            logger.info(
                "Set the server hostname to \(serverHostname) and the port to \(serverPort) via proxy \(proxy)"
            )
        } else {
            logger.info(
                "Set the server hostname to \(serverHostname) and the port to \(serverPort)")
        }
    }

    public func close() {

        // Nothing at the moment - most likely we should close the websocket here
    }

    public func getHostname() -> String {
        return self.serverHostname
    }


    /**
     Helper function to URL encode a string
     */
    public func urlEncode(_ string: String) -> String? {
        return string.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
    }

    /**
     Creates a configured URLRequest with proper headers for proxy support
    
     This method ensures all HTTP requests to the server include the necessary headers
     for proxy authentication and routing, regardless of where in the app they originate.
    
     - Parameter url: The URL to create the request for
     - Returns: A URLRequest configured with API key and Host headers as needed
     */
    public func createConfiguredURLRequest(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)

        // Add API key header if configured
        if let key = apiKey {
            request.setValue(key, forHTTPHeaderField: "x-acw-api-key")
        }

        // Set Host header when using proxy
        if serverProxyHost != nil, apiKey != nil {
            request.setValue("\(serverHostname):\(serverPort)", forHTTPHeaderField: "Host")
        }

        // Inject W3C Trace Context headers (traceparent, tracestate) for distributed
        // tracing. When OTel is not bootstrapped, the no-op instrument skips injection.
        if let context = ServiceContext.current {
            var headers: [String: String] = [:]
            InstrumentationSystem.instrument.inject(
                context, into: &headers, using: HTTPHeadersInjector())
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }

        return request
    }


    func fetchData<T: Decodable>(_ url: URL, returnType: T.Type) async -> Result<T, ServerError> {
        let response = await fetchDataResponse(url)
        switch response {
        case .success(let response):
            return decodeResponse(response.data, returnType: returnType)
        case .failure(let error):
            return .failure(error)
        }
    }


    // Generic method to send data via a POST request and decode the response
    func sendData<T: Decodable, U: Encodable>(
        _ url: URL, method: String = "POST", body: U, returnType: T.Type
    ) async -> Result<T, ServerError> {
        let response = await sendDataResponse(url, method: method, body: body)
        switch response {
        case .success(let response):
            return decodeResponse(response.data, returnType: returnType)
        case .failure(let error):
            return .failure(error)
        }
    }


    func sendRawJson<T: Decodable>(
        _ url: URL, method: String = "POST", rawJson: String, returnType: T.Type
    ) async -> Result<T, ServerError> {
        let response = await sendRawJsonResponse(url, method: method, rawJson: rawJson)
        switch response {
        case .success(let response):
            return decodeResponse(response.data, returnType: returnType)
        case .failure(let error):
            return .failure(error)
        }
    }

    func fetchDataResponse(_ url: URL) async -> Result<HTTPResponseData, ServerError> {
        var request = createConfiguredURLRequest(for: url)
        // Never serve these REST reads from the URL cache. The server doesn't send
        // cache-control headers, so CFNetwork heuristically caches 200s and can hand a
        // stale list back to a cache rebuild right after a save — leaving SwiftData behind
        // (e.g. a newly-added tile missing in perform mode). Our SwiftData layer *is* the
        // cache, refreshed via the websocket invalidation model; the HTTP layer must always
        // hit the origin.
        request.cachePolicy = .reloadIgnoringLocalCacheData

        return await performRequest(
            request,
            method: "GET",
            url: url,
            successStatusCodes: [200]
        )
    }

    func sendDataResponse<U: Encodable>(
        _ url: URL,
        method: String = "POST",
        body: U,
        successStatusCodes: Set<Int> = [200, 201, 202]
    ) async -> Result<HTTPResponseData, ServerError> {
        let requestBody: Data
        do {
            requestBody = try JSONEncoder().encode(body)
        } catch {
            logger.error("Encoding error: \(error.localizedDescription)")
            return .failure(.dataFormatError("Encoding error: \(error.localizedDescription)"))
        }

        var request = createConfiguredURLRequest(for: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = requestBody

        return await performRequest(
            request,
            method: method,
            url: url,
            successStatusCodes: successStatusCodes
        )
    }

    func sendRawJsonResponse(
        _ url: URL,
        method: String = "POST",
        rawJson: String,
        successStatusCodes: Set<Int> = [200, 201, 202]
    ) async -> Result<HTTPResponseData, ServerError> {
        guard let requestBody = rawJson.data(using: .utf8) else {
            return .failure(.dataFormatError("Unable to encode raw JSON body"))
        }

        var request = createConfiguredURLRequest(for: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = requestBody

        return await performRequest(
            request,
            method: method,
            url: url,
            successStatusCodes: successStatusCodes
        )
    }

    func sendBinaryDataResponse(
        _ url: URL,
        method: String = "POST",
        body: Data,
        contentType: String,
        successStatusCodes: Set<Int> = [200, 201, 202]
    ) async -> Result<HTTPResponseData, ServerError> {
        var request = createConfiguredURLRequest(for: url)
        request.httpMethod = method
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        return await performRequest(
            request,
            method: method,
            url: url,
            successStatusCodes: successStatusCodes
        )
    }

    private func performRequest(
        _ request: URLRequest,
        method: String,
        url: URL,
        successStatusCodes: Set<Int>
    ) async -> Result<HTTPResponseData, ServerError> {
        await withSpan("HTTP \(method) \(url.path)") { span in
            span.attributes["http.method"] = method
            span.attributes["http.url"] = url.absoluteString

            let responseResult = await executeRequest(request, url: url)
            switch responseResult {
            case .failure(let error):
                span.recordError(error)
                return .failure(error)

            case .success(let response):
                span.attributes["http.status_code"] = response.statusCode

                guard successStatusCodes.contains(response.statusCode) else {
                    let error = serverError(for: response)
                    span.recordError(error)
                    logger.error(
                        "HTTP \(response.statusCode) from \(url): \(error.localizedDescription)")
                    return .failure(error)
                }

                return .success(response)
            }
        }
    }

    private func executeRequest(
        _ request: URLRequest,
        url: URL
    ) async -> Result<HTTPResponseData, ServerError> {
        do {
            let (data, response) = try await httpDataLoader(request)

            guard let httpResponse = response as? HTTPURLResponse else {
                logger.error("Invalid response from \(url)")
                return .failure(.serverError("Invalid response from \(url)"))
            }

            return .success(
                HTTPResponseData(
                    data: data,
                    statusCode: httpResponse.statusCode,
                    contentDisposition: httpResponse.value(
                        forHTTPHeaderField: "Content-Disposition")
                )
            )
        } catch {
            logger.error("Request error: \(error.localizedDescription)")
            return .failure(.communicationError("Request error: \(error.localizedDescription)"))
        }
    }

    func decodeResponse<T: Decodable>(
        _ data: Data,
        returnType: T.Type
    ) -> Result<T, ServerError> {
        do {
            let result = try makeJSONDecoder().decode(T.self, from: data)
            return .success(result)
        } catch {
            let message = decodingErrorMessage(error)
            logger.error("\(message)")
            return .failure(.serverError(message))
        }
    }

    private func serverError(for response: HTTPResponseData) -> ServerError {
        let status = try? makeJSONDecoder().decode(StatusDTO.self, from: response.data)
        let message = status?.message

        switch response.statusCode {
        case 400, 422:
            return .dataFormatError(message ?? "Data format error")
        case 404:
            return .notFound(message ?? "Resource not found")
        case 409:
            return .conflict(message ?? "Request conflicts with current server state")
        case 501:
            return .notImplemented(message ?? "Not implemented")
        case 500...599:
            return .serverError(message ?? "Server error")
        default:
            return .serverError(message ?? "Unexpected status code \(response.statusCode)")
        }
    }

    func makeJSONDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func decodingErrorMessage(_ error: Error) -> String {
        guard let decodingError = error as? DecodingError else {
            return "Decoding error: \(error.localizedDescription)"
        }

        switch decodingError {
        case .typeMismatch(let type, let context):
            return
                "Decoding error: Type mismatch for type \(type): \(context.debugDescription) - coding path: \(context.codingPath)"
        case .valueNotFound(let type, let context):
            return
                "Decoding error: Value not found for type \(type): \(context.debugDescription) - coding path: \(context.codingPath)"
        case .keyNotFound(let key, let context):
            return
                "Decoding error: Key '\(key.stringValue)' not found: \(context.debugDescription) - coding path: \(context.codingPath)"
        case .dataCorrupted(let context):
            return
                "Decoding error: Data corrupted: \(context.debugDescription) - coding path: \(context.codingPath)"
        @unknown default:
            return "Decoding error: Unknown decoding error."
        }
    }

}

/// Injector for W3C Trace Context propagation into HTTP header dictionaries.
private struct HTTPHeadersInjector: Instrumentation.Injector {
    typealias Carrier = [String: String]

    func inject(_ value: String, forKey key: String, into carrier: inout [String: String]) {
        carrier[key] = value
    }
}
