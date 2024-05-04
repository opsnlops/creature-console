
import Foundation
import OSLog


extension CreatureServerRestful {


    /**
     List all of the sounds on the server
     */
    func listSounds() async -> Result<[Sound], ServerError> {

        logger.debug("attempting to get all of the creatures")

        guard let url = URL(string: makeBaseURL() + "/sound") else {
            return .failure(.serverError("unable to make base URL"))
        }
        self.logger.debug("Using URL: \(url)")

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse else {
                self.logger.error("HTTP Error while trying to list the available sounds")
                return .failure(.serverError("HTTP error while playing a sound"))
            }

            // Woot, make a JSONDecoder and get ready for some fun
            let decoder = JSONDecoder()

            do {
                switch(httpResponse.statusCode) {

                case 200:
                    let list = try decoder.decode(SoundListDTO.self, from: data)
                    logger.debug("Found \(list.count) sounds")
                    return .success(list.items)

                case 404:
                    let status = try decoder.decode(StatusDTO.self, from: data)
                    logger.warning("No sounds found on the remote server: \(status.message)")
                    return .failure(.notFound(status.message))

                case 500:
                    let status = try decoder.decode(StatusDTO.self, from: data)
                    logger.error("Server error while trying to get the list of sounds: \(status.message)")
                    return .failure(.serverError(status.message))

                default:
                    self.logger.error("unexpected return code from \(url) while attempting to play a sound: \(httpResponse.statusCode)")
                    return .failure(.serverError("Unexepcted status code while playing sound: \(httpResponse.statusCode)"))
                }

            } catch {
                return .failure(.serverError(error.localizedDescription))
            }
        } catch {
            return .failure(.serverError(error.localizedDescription))
        }
    }

    /**
     Play one of the sounds on the server
     */
    func playSound(_ fileName: String) async -> Result<String, ServerError> {

        logger.debug("attempting play sound \(fileName) on server")

        // Make sure we can encode the fileName
        guard let soundFileName = urlEncode(fileName) else {
            return .failure(.dataFormatError("fileName can't be URL Encoded"))
        }
        self.logger.debug("encoded filename: \(soundFileName)")

        // Construct the URL
        guard let url = URL(string: makeBaseURL() + "/sound/play/\(soundFileName)") else {
            return .failure(.serverError("unable to make base URL"))
        }
        self.logger.debug("Using URL: \(url)")

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse else {
                self.logger.error("HTTP Error while trying to talk to server while playing a sound")
                return .failure(.serverError("HTTP error while playing a sound"))
            }

            // This only returns a StatusDTO
            do {
                switch(httpResponse.statusCode) {

                case 200:
                    let decoder = JSONDecoder()
                    let status = try decoder.decode(StatusDTO.self, from: data)
                    self.logger.debug("got a 200 while playing a sound file: \(status.message)")
                    return .success(status.message)

                case 404:
                    let decoder = JSONDecoder()
                    let status = try decoder.decode(StatusDTO.self, from: data)
                    self.logger.warning("got a 404 while playing a sound file: \(status.message)")
                    return .failure(.notFound(status.message))

                case 500:
                    let decoder = JSONDecoder()
                    let status = try decoder.decode(StatusDTO.self, from: data)
                    self.logger.error("got a 500 while playing a sound file: \(status.message)")
                    return .failure(.serverError(status.message))

                default:
                    self.logger.error("unexpected return code from \(url) while attempting to play a sound: \(httpResponse.statusCode)")
                    return .failure(.serverError("Unexepcted status code while playing sound: \(httpResponse.statusCode)"))
                }

            } catch {
                self.logger.error("unable to play sound: \(error.localizedDescription)")
                return .failure(.serverError(error.localizedDescription))
            }
        } catch {
            self.logger.error("unable to play sound: \(error.localizedDescription)")
            return .failure(.serverError(error.localizedDescription))
        }
    }

}

