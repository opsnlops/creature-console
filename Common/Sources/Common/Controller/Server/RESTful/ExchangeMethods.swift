import Foundation
import Logging

extension CreatureServerClient {

    /**
     List recent streamed ad-hoc exchanges, newest first.

     One exchange per streaming session, including in-flight ones (status
     `streaming`). The list shares the ad-hoc TTL, so it's naturally "recent."
     */
    public func listAdHocExchanges() async -> Result<[AdHocExchange], ServerError> {

        logger.debug("attempting to get the list of ad-hoc exchanges")

        return await fetchData(
            path: "/animation/ad-hoc-stream/exchanges",
            returnType: AdHocExchangeListDTO.self
        ).map { $0.items }
    }

    /**
     Fetch one streamed ad-hoc exchange — full transcript and parts.
     */
    public func getAdHocExchange(sessionId: String) async -> Result<AdHocExchange, ServerError> {

        logger.debug("attempting to get ad-hoc exchange \(sessionId)")

        guard let encodedId = urlEncode(sessionId) else {
            return .failure(.serverError("unable to make base URL"))
        }

        return await fetchData(
            path: "/animation/ad-hoc-stream/exchange/" + encodedId,
            returnType: AdHocExchange.self
        )
    }

    /**
     Returns the URL of a whole exchange's stitched audio in the given format.
     */
    public func getExchangeAudioURL(sessionId: String, format: ExchangeAudioFormat) -> Result<
        URL, ServerError
    > {

        logger.debug("attempting to get \(format.rawValue) audio URL for exchange \(sessionId)")

        guard let encodedId = urlEncode(sessionId),
            let url = URL(
                string: makeBaseURL(.http) + "/animation/ad-hoc-stream/exchange/" + encodedId + "/"
                    + format.routeFilename)
        else {
            return .failure(.serverError("unable to make base URL"))
        }

        logger.debug("exchange \(format.rawValue) audio URL: \(url)")
        return .success(url)
    }

    /**
     Download a whole exchange's stitched audio, ready to write to disk.

     The server stitches every sentence of the session into one fully-tagged
     file (ID3 title/artist/lyrics on the MP3). While the session is still
     `streaming` the route answers 409, which surfaces here as `.conflict`
     carrying the server's message — report it, don't retry-loop.
     */
    public func downloadExchangeAudio(sessionId: String, format: ExchangeAudioFormat) async
        -> Result<ShareableSound, ServerError>
    {

        logger.debug(
            "attempting to download the \(format.rawValue) audio of exchange \(sessionId)")

        guard let encodedId = urlEncode(sessionId) else {
            return .failure(.serverError("unable to make base URL"))
        }

        // Exchange audio is immutable once the session is ready (the server marks it
        // `Cache-Control: public, immutable`), so honor the cache rather than force-reloading.
        return await fetchDataResponse(
            path: "/animation/ad-hoc-stream/exchange/" + encodedId + "/" + format.routeFilename,
            cachePolicy: .useProtocolCachePolicy
        ).map { response in
            let suggested =
                parseFilenameFromContentDisposition(response.contentDisposition)
                ?? format.filename(forSessionId: sessionId)
            return ShareableSound(data: response.data, suggestedFilename: suggested)
        }
    }

}
