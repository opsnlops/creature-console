import Foundation
import Logging

public class CreatureServerClient: CreatureServerClientProtocol {

    public static let shared = CreatureServerClient()

    // WebSocket processing stuff
    var processor: MessageProcessor?
    var webSocketClient: WebSocketClient?

    var logger: Logger
    public var serverHostname: String =
        UserDefaults.standard.string(forKey: "serverHostname") ?? "127.0.0.1"
    public var serverPort: Int = UserDefaults.standard.integer(forKey: "serverRestPort")
    public var useTLS: Bool = true


    public enum UrlType {
        case http
        case websocket
    }


    public init() {
        self.logger = Logger(label: "io.opsnlops.creature-controller.common")
        self.logger.logLevel = .debug
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

        return "\(prefix)\(serverHostname):\(serverPort)/api/v1"
    }

    public func connect(serverHostname: String, serverPort: Int, useTLS: Bool) throws {
        self.serverHostname = serverHostname
        self.serverPort = serverPort
        self.useTLS = useTLS
        logger.info("Set the server hostname to \(serverHostname) and the port to \(serverPort)")
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


    func fetchData<T: Decodable>(_ url: URL, returnType: T.Type) async -> Result<T, ServerError> {

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse else {
                logger.error("Invalid response for \(url)")
                return .failure(.serverError("Invalid response for \(url)"))
            }

            let decoder = JSONDecoder()

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
            var request = URLRequest(url: url)
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

            case 200:
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
