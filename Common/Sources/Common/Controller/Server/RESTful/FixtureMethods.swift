import Foundation
import Logging

private struct EmptyBody: Encodable {}

extension CreatureServerClient {

    public func getAllFixtures() async -> Result<[DmxFixture], ServerError> {
        logger.debug("attempting to get all of the fixtures")

        return await fetchData(path: "/fixture", returnType: DmxFixtureListDTO.self).map {
            $0.items
        }
    }

    public func getFixture(id: DmxFixtureIdentifier) async -> Result<DmxFixture, ServerError> {
        logger.debug("attempting to load fixture \(id)")

        return await fetchData(path: "/fixture/\(id)", returnType: DmxFixture.self)
    }

    public func upsertFixture(_ fixture: DmxFixture) async -> Result<DmxFixture, ServerError> {
        logger.debug("attempting to upsert fixture \(fixture.id)")

        return await sendData(
            path: "/fixture", method: "POST", body: fixture, returnType: DmxFixture.self)
    }

    public func deleteFixture(id: DmxFixtureIdentifier) async -> Result<String, ServerError> {
        logger.debug("attempting to delete fixture \(id)")

        return await sendData(
            path: "/fixture/\(id)", method: "DELETE", body: EmptyBody(), returnType: StatusDTO.self
        ).map { $0.message }
    }

    public func validateFixture(rawJson: String) async -> Result<
        FixtureConfigValidationDTO, ServerError
    > {
        return await sendRawJson(
            path: "/fixture/validate", method: "POST", rawJson: rawJson,
            returnType: FixtureConfigValidationDTO.self)
    }

    /// Returns the updated fixture (server convention — every state-changing fixture
    /// endpoint returns the full `DmxFixtureDto` on 200, not a `StatusDto`).
    public func setFixtureUniverse(id: DmxFixtureIdentifier, universe: UInt32) async -> Result<
        DmxFixture, ServerError
    > {
        logger.debug("setting universe \(universe) on fixture \(id)")

        let body = SetFixtureUniverseDTO(universe: universe)
        return await sendData(
            path: "/fixture/\(id)/universe", method: "PUT", body: body, returnType: DmxFixture.self)
    }

    public func clearFixtureUniverse(id: DmxFixtureIdentifier) async -> Result<
        DmxFixture, ServerError
    > {
        logger.debug("clearing universe on fixture \(id)")

        return await sendData(
            path: "/fixture/\(id)/universe", method: "DELETE", body: EmptyBody(),
            returnType: DmxFixture.self)
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

        let body = SetFixtureLiveDTO(values: values, timeoutMs: timeoutMs)
        return await sendData(
            path: "/fixture/\(id)/live", method: "POST", body: body, returnType: DmxFixture.self)
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

        let body = PreviewFixturePatternDTO(
            values: values,
            fadeInMs: fadeInMs,
            fadeOutMs: fadeOutMs,
            holdMs: holdMs,
            stopAfterMs: stopAfterMs
        )
        return await sendData(
            path: "/fixture/\(fixtureId)/pattern/preview", method: "POST", body: body,
            returnType: DmxFixture.self)
    }

    public func triggerFixturePattern(
        fixtureId: DmxFixtureIdentifier,
        patternId: FixturePatternIdentifier,
        stopAfterMs: UInt32? = nil
    ) async -> Result<DmxFixture, ServerError> {
        logger.debug(
            "triggering pattern \(patternId) on fixture \(fixtureId), stopAfterMs=\(stopAfterMs.map(String.init) ?? "nil")"
        )

        let body = TriggerFixturePatternDTO(stopAfterMs: stopAfterMs)
        return await sendData(
            path: "/fixture/\(fixtureId)/pattern/\(patternId)/trigger", method: "POST", body: body,
            returnType: DmxFixture.self)
    }
}
