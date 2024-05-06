
import Combine
import Foundation
import OSLog

class CreatureServerRestful : CreatureServerClientProtocol {

    static let shared = CreatureServerRestful()
    var webSocketTask: URLSessionWebSocketTask?
    var cancellables: Set<AnyCancellable> = []

    let logger: Logger
    var serverHostname: String = UserDefaults.standard.string(forKey: "serverHostname") ?? "127.0.0.1"
    var serverPort: Int = UserDefaults.standard.integer(forKey: "serverRestPort")
    var useTLS: Bool = UserDefaults.standard.bool(forKey: "serverUseTLS")


    enum UrlType {
        case http
        case websocket
    }


    init() {
        self.logger = Logger(subsystem: "io.opsnlops.CreatureController", category: "CreatureServerRestful")
        self.logger.info("Created new CreatureServerRestful")
    }

    /**
     Returns the URL to our server

     @param type Which type of URL to make (http or websocket)
     */
    func makeBaseURL(_ type: UrlType) -> String {

        var prefix: String
        switch(type) {
        case(.http):
            prefix = useTLS ? "https://" : "http://"
        case(.websocket):
            prefix = useTLS ? "wss://" : "ws://"
        }

        return "\(prefix)\(serverHostname):\(serverPort)/api/v1"
    }

    func connect(serverHostname: String, serverPort: Int) throws {
        self.serverHostname = serverHostname
        self.serverPort = serverPort
        logger.info("Set the server hostname to \(serverHostname) and the port to \(serverPort)")
    }

    func close() throws {

        // Nothing at the moment - most likely we should close the websocket here
    }

    func getHostname() -> String {
        return self.serverHostname
    }


    /**
     Helper function to URL encode a string
     */
    func urlEncode(_ string: String) -> String? {
        return string.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
    }


    /**
     Print out dates in my local time zone
     */
    func formatToLocalTime(_ date: Date) -> String {

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss ZZZZ"

        // Set the formatter's time zone to the system's current local time zone
        formatter.timeZone = TimeZone.current

        return formatter.string(from: date)
    }
}
