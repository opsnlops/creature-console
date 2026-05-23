import Foundation
import Logging

private struct EmptyBody: Encodable {}

extension CreatureServerClient {

    public func getAllFixtures() async -> Result<[DmxFixture], ServerError> {
        logger.debug("attempting to get all of the fixtures")

        guard let url = URL(string: makeBaseURL(.http) + "/fixture") else {
            return .failure(.serverError("unable to make base URL"))
        }
        self.logger.debug("Using URL: \(url)")

        return await fetchData(url, returnType: DmxFixtureListDTO.self).map { $0.items }
    }

    public func getFixture(id: DmxFixtureIdentifier) async -> Result<DmxFixture, ServerError> {
        logger.debug("attempting to load fixture \(id)")

        guard let url = URL(string: makeBaseURL(.http) + "/fixture/\(id)") else {
            return .failure(.serverError("unable to make base URL"))
        }
        self.logger.debug("Using URL: \(url)")

        return await fetchData(url, returnType: DmxFixture.self)
    }

    public func upsertFixture(_ fixture: DmxFixture) async -> Result<DmxFixture, ServerError> {
        logger.debug("attempting to upsert fixture \(fixture.id)")

        guard let url = URL(string: makeBaseURL(.http) + "/fixture") else {
            return .failure(.serverError("unable to make base URL"))
        }
        self.logger.debug("Using URL: \(url)")

        return await sendData(
            url, method: "POST", body: fixture, returnType: DmxFixture.self)
    }

    public func deleteFixture(id: DmxFixtureIdentifier) async -> Result<String, ServerError> {
        logger.debug("attempting to delete fixture \(id)")

        guard let url = URL(string: makeBaseURL(.http) + "/fixture/\(id)") else {
            return .failure(.serverError("unable to make base URL"))
        }
        self.logger.debug("Using URL: \(url)")

        return await sendData(
            url, method: "DELETE", body: EmptyBody(), returnType: StatusDTO.self
        ).map { $0.message }
    }

    public func validateFixture(rawJson: String) async -> Result<
        FixtureConfigValidationDTO, ServerError
    > {
        guard let url = URL(string: makeBaseURL(.http) + "/fixture/validate") else {
            return .failure(.serverError("unable to make base URL"))
        }
        logger.debug("Using URL: \(url)")

        return await sendRawJson(
            url, method: "POST", rawJson: rawJson, returnType: FixtureConfigValidationDTO.self)
    }

    /// Returns the updated fixture (server convention — every state-changing fixture
    /// endpoint returns the full `DmxFixtureDto` on 200, not a `StatusDto`).
    public func setFixtureUniverse(id: DmxFixtureIdentifier, universe: UInt32) async -> Result<
        DmxFixture, ServerError
    > {
        logger.debug("setting universe \(universe) on fixture \(id)")

        guard let url = URL(string: makeBaseURL(.http) + "/fixture/\(id)/universe") else {
            return .failure(.serverError("unable to make base URL"))
        }
        self.logger.debug("Using URL: \(url)")

        let body = SetFixtureUniverseDTO(universe: universe)
        return await sendData(url, method: "PUT", body: body, returnType: DmxFixture.self)
    }

    public func clearFixtureUniverse(id: DmxFixtureIdentifier) async -> Result<
        DmxFixture, ServerError
    > {
        logger.debug("clearing universe on fixture \(id)")

        guard let url = URL(string: makeBaseURL(.http) + "/fixture/\(id)/universe") else {
            return .failure(.serverError("unable to make base URL"))
        }
        self.logger.debug("Using URL: \(url)")

        return await sendData(
            url, method: "DELETE", body: EmptyBody(), returnType: DmxFixture.self)
    }

    /// Live slider control. `timeoutMs` must be in `(0, 600000]` ms — the server holds
    /// the supplied channel values until the deadline elapses, then blacks out. While
    /// live is in effect on a fixture, pattern triggers (manual and binding-driven) are
    /// refused with 400. Returns the fixture document (DTO), same as other mutating
    /// fixture endpoints.
    public func setFixtureLive(
        id: DmxFixtureIdentifier,
        values: [FixturePatternValue],
        timeoutMs: UInt32
    ) async -> Result<DmxFixture, ServerError> {
        logger.debug(
            "live update on fixture \(id): \(values.count) value(s), timeoutMs=\(timeoutMs)")

        guard let url = URL(string: makeBaseURL(.http) + "/fixture/\(id)/live") else {
            return .failure(.serverError("unable to make base URL"))
        }
        self.logger.debug("Using URL: \(url)")

        let body = SetFixtureLiveDTO(values: values, timeoutMs: timeoutMs)
        return await sendData(url, method: "POST", body: body, returnType: DmxFixture.self)
    }

    /// Fires an ephemeral pattern constructed from the supplied values + fade timings
    /// without persisting anything. Lets the pattern editor's Fire button preview
    /// unsaved local edits — the editor stays the source of truth during editing,
    /// and saved patterns aren't disturbed until the user explicitly saves. Returns
    /// the fixture document (matching other state-changing fixture endpoints).
    public func previewFixturePattern(
        fixtureId: DmxFixtureIdentifier,
        values: [FixturePatternValue],
        fadeInMs: UInt32 = 0,
        fadeOutMs: UInt32 = 0,
        holdMs: UInt32 = 0,
        stopAfterMs: UInt32? = nil
    ) async -> Result<DmxFixture, ServerError> {
        logger.debug(
            "previewing pattern on fixture \(fixtureId): \(values.count) value(s), fadeIn=\(fadeInMs) fadeOut=\(fadeOutMs) hold=\(holdMs) stopAfter=\(stopAfterMs.map(String.init) ?? "nil")"
        )

        guard
            let url = URL(string: makeBaseURL(.http) + "/fixture/\(fixtureId)/pattern/preview")
        else {
            return .failure(.serverError("unable to make base URL"))
        }
        self.logger.debug("Using URL: \(url)")

        let body = PreviewFixturePatternDTO(
            values: values,
            fadeInMs: fadeInMs,
            fadeOutMs: fadeOutMs,
            holdMs: holdMs,
            stopAfterMs: stopAfterMs
        )
        return await sendData(url, method: "POST", body: body, returnType: DmxFixture.self)
    }

    public func triggerFixturePattern(
        fixtureId: DmxFixtureIdentifier,
        patternId: FixturePatternIdentifier,
        stopAfterMs: UInt32? = nil
    ) async -> Result<DmxFixture, ServerError> {
        logger.debug(
            "triggering pattern \(patternId) on fixture \(fixtureId), stopAfterMs=\(stopAfterMs.map(String.init) ?? "nil")"
        )

        guard
            let url = URL(
                string: makeBaseURL(.http) + "/fixture/\(fixtureId)/pattern/\(patternId)/trigger")
        else {
            return .failure(.serverError("unable to make base URL"))
        }
        self.logger.debug("Using URL: \(url)")

        let body = TriggerFixturePatternDTO(stopAfterMs: stopAfterMs)
        return await sendData(url, method: "POST", body: body, returnType: DmxFixture.self)
    }
}
