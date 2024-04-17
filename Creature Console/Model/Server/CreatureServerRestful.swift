
import Foundation
import Combine
import OSLog

class CreatureServerRestful {

    let logger: Logger
    var serverHostname: String = UserDefaults.standard.string(forKey: "serverHostname") ?? "127.0.0.1"
    var serverPort: Int = UserDefaults.standard.integer(forKey: "serverRestPort")
    var useTLS: Bool = UserDefaults.standard.bool(forKey: "serverUseTLS")

    init() {
        self.logger = Logger(subsystem: "io.opsnlops.CreatureController", category: "CreatureServerRestful")
        self.logger.info("Created new CreatureServerRestful")
    }

    func makeBaseURL() -> String {
        let prefix: String = useTLS ? "https://" : "http://"
        return "\(prefix)\(serverHostname):\(serverPort)/api/v1"
    }

    func fetchAllCreatures() async -> Result<[Creature], ServerError> {

        logger.debug("attempting to get all of the creatures")

        guard let url = URL(string: makeBaseURL() + "/creature") else {
            return .failure(.serverError("unable to make base URL"))
        }
        self.logger.debug("Using URL: \(url)")

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                self.logger.debug("return code was \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                return .failure(.serverError("non-200 return code"))
            }

            do {
                let decoder = JSONDecoder()
                let creatures = try decoder.decode([Creature].self, from: data)
                return .success(creatures)
            } catch {
                return .failure(.serverError(error.localizedDescription))
            }
        } catch {
            return .failure(.serverError(error.localizedDescription))
        }
    }


}
