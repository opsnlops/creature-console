import Foundation
import Logging

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

public final class CreatureServerClient: CreatureServerClientProtocol, Sendable {

    public static let shared = CreatureServerClient()

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


    public init() {
        var logger = Logging.Logger(label: "io.opsnlops.creature-controller.common")
        logger.logLevel = .debug
        self.logger = logger
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

        return request
    }


    func fetchData<T: Decodable>(_ url: URL, returnType: T.Type) async -> Result<T, ServerError> {

        do {
            let request = createConfiguredURLRequest(for: url)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                logger.error("Invalid response for \(url)")
                return .failure(.serverError("Invalid response for \(url)"))
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            switch httpResponse.statusCode {

            case 200:
                do {

                    let result = try decoder.decode(T.self, from: data)
                    return .success(result)

                } catch let decodingError as DecodingError {
                    var errorMessage = "Decoding Error: "
                    switch decodingError {
                    case .typeMismatch(let type, let context):
                        errorMessage +=
                            "Type mismatch for type \(type): \(context.debugDescription) - coding path: \(context.codingPath)"
                    case .valueNotFound(let type, let context):
                        errorMessage +=
                            "Value not found for type \(type): \(context.debugDescription) - coding path: \(context.codingPath)"
                    case .keyNotFound(let key, let context):
                        errorMessage +=
                            "Key '\(key.stringValue)' not found: \(context.debugDescription) - coding path: \(context.codingPath)"
                    case .dataCorrupted(let context):
                        errorMessage +=
                            "Data corrupted: \(context.debugDescription) - coding path: \(context.codingPath)"
                    @unknown default:
                        errorMessage += "Unknown decoding error."
                    }
                    logger.error("\(errorMessage)")
                    return .failure(.serverError(errorMessage))
                } catch {
                    return .failure(.serverError("Decoding error: \(error.localizedDescription)"))
                }

            case 404:
                do {
                    let status = try decoder.decode(StatusDTO.self, from: data)
                    return .failure(.notFound(status.message))
                } catch {
                    return .failure(.notFound("Resource not found"))
                }

            case 500:
                do {
                    let status = try decoder.decode(StatusDTO.self, from: data)
                    return .failure(.serverError(status.message))
                } catch {
                    return .failure(.serverError("Server error"))
                }

            default:
                return .failure(.serverError("Unexpected status code \(httpResponse.statusCode)"))
            }

        } catch {
            return .failure(.serverError(error.localizedDescription))
        }
    }


    // Generic method to send data via a POST request and decode the response
    func sendData<T: Decodable, U: Encodable>(
        _ url: URL, method: String = "POST", body: U, returnType: T.Type
    ) async -> Result<T, ServerError> {
        do {
            // Convert the request body to JSON data
            let encoder = JSONEncoder()
            let requestBody = try encoder.encode(body)

            // Set up a URLRequest with a POST method
            var request = createConfiguredURLRequest(for: url)
            request.httpMethod = method
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = requestBody

            // Perform the request
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                logger.error("Invalid response from \(url)")
                return .failure(.serverError("Invalid response from \(url)"))
            }

            // Decode the server's response
            let decoder = JSONDecoder()
            switch httpResponse.statusCode {

            case 200, 201, 202:
                do {
                    let result = try decoder.decode(T.self, from: data)
                    return .success(result)
                } catch {
                    logger.error("Decoding error: \(error.localizedDescription)")
                    return .failure(.serverError("Decoding error: \(error.localizedDescription)"))
                }

            case 400:
                let status = try? decoder.decode(StatusDTO.self, from: data)
                return .failure(.dataFormatError(status?.message ?? "Data format error"))

            case 404:
                let status = try? decoder.decode(StatusDTO.self, from: data)
                return .failure(.notFound(status?.message ?? "Resource not found"))

            case 422:
                let status = try? decoder.decode(StatusDTO.self, from: data)
                return .failure(
                    .dataFormatError(status?.message ?? "Request could not be processed"))

            case 409:
                let status = try? decoder.decode(StatusDTO.self, from: data)
                return .failure(
                    .conflict(status?.message ?? "Request conflicts with current server state"))

            case 500:
                let status = try? decoder.decode(StatusDTO.self, from: data)
                return .failure(.serverError(status?.message ?? "Server error"))

            default:
                logger.error("Unexpected status code \(httpResponse.statusCode) from \(url)")
                return .failure(.serverError("Unexpected status code \(httpResponse.statusCode)"))
            }

        } catch {
            logger.error("Request error: \(error.localizedDescription)")
            return .failure(.serverError("Request error: \(error.localizedDescription)"))
        }
    }


    func sendRawJson<T: Decodable>(
        _ url: URL, method: String = "POST", rawJson: String, returnType: T.Type
    ) async -> Result<T, ServerError> {
        guard let requestBody = rawJson.data(using: .utf8) else {
            return .failure(.dataFormatError("Unable to encode raw JSON body"))
        }

        do {
            var request = createConfiguredURLRequest(for: url)
            request.httpMethod = method
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = requestBody

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                logger.error("Invalid response from \(url)")
                return .failure(.serverError("Invalid response from \(url)"))
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            switch httpResponse.statusCode {

            case 200, 201, 202:
                do {
                    let result = try decoder.decode(T.self, from: data)
                    return .success(result)
                } catch {
                    logger.error("Decoding error: \(error.localizedDescription)")
                    return .failure(.serverError("Decoding error: \(error.localizedDescription)"))
                }

            case 400:
                let status = try? decoder.decode(StatusDTO.self, from: data)
                return .failure(.dataFormatError(status?.message ?? "Data format error"))

            case 404:
                let status = try? decoder.decode(StatusDTO.self, from: data)
                return .failure(.notFound(status?.message ?? "Resource not found"))

            case 422:
                let status = try? decoder.decode(StatusDTO.self, from: data)
                return .failure(
                    .dataFormatError(status?.message ?? "Request could not be processed"))

            case 409:
                let status = try? decoder.decode(StatusDTO.self, from: data)
                return .failure(
                    .conflict(status?.message ?? "Request conflicts with current server state"))

            case 500:
                let status = try? decoder.decode(StatusDTO.self, from: data)
                return .failure(.serverError(status?.message ?? "Server error"))

            default:
                logger.error("Unexpected status code \(httpResponse.statusCode) from \(url)")
                return .failure(.serverError("Unexpected status code \(httpResponse.statusCode)"))
            }

        } catch {
            logger.error("Request error: \(error.localizedDescription)")
            return .failure(.serverError("Request error: \(error.localizedDescription)"))
        }
    }


}
