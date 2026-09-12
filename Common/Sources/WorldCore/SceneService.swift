import Foundation
import Tracing

public protocol SceneRepository: Sendable {
    func scene(id: SceneID) async throws -> Scene?
    func save(_ scene: Scene) async throws
    /// Open scenes in a region, oldest first.
    func openScenes(in regionID: EntityID) async throws -> [Scene]
    /// Most recent scenes, newest first.
    func recentScenes(limit: Int) async throws -> [Scene]
}

/// Something that can carry a scene into the room. Told when a scene opens, each time a
/// character speaks, and when the scene closes; a performer may play turns as they arrive
/// (Creature Server's `dialog-stream`) or render the whole scene at the end (`dialog`).
public protocol ScenePerforming: Sendable {
    /// The scene has opened with these participants. Failure here must not stop the scene.
    func sceneOpened(_ scene: Scene) async
    /// A character spoke. Failure here must not stop the scene.
    func sceneTurn(_ scene: Scene, _ turn: SceneTurn) async
    /// The scene has closed with at least one spoken turn; play or finish playing it.
    func sceneClosed(_ scene: Scene) async throws -> ScenePerformance
}

/// The world's stage manager: opens a scene when more than one character could answer, gives the
/// floor to one character at a time, records what each says, closes the scene on April's
/// cutoffs, and hands the finished scene to the performer. Minds decide *what*; this decides
/// *who* and *when*.
public actor SceneService {
    public static let openedEventType = WorldEventType(rawValue: "scene.opened")!
    public static let turnEventType = WorldEventType(rawValue: "scene.turn")!
    public static let closedEventType = WorldEventType(rawValue: "scene.closed")!
    public static let performedEventType = WorldEventType(rawValue: "scene.performed")!
    public static let floorExpiredEventType = WorldEventType(rawValue: "scene.floor_expired")!
    public static let sourceID = try! SourceID(validating: "world:scenes")

    private let repository: any SceneRepository
    private let clock: any WorldClock
    private let limits: SceneLimits
    private let announce: @Sendable (WorldEventEnvelope) async throws -> Void
    private let scheduleDeadline: @Sendable (WorldTimer) async throws -> Void
    private let recordTurn: @Sendable (Scene, SceneTurn) async throws -> ConversationItemID
    private let performer: any ScenePerforming
    private let makeResponseID: @Sendable () -> ResponseID

    public init(
        repository: any SceneRepository,
        clock: any WorldClock,
        limits: SceneLimits = SceneLimits(),
        performer: any ScenePerforming,
        announce: @escaping @Sendable (WorldEventEnvelope) async throws -> Void,
        scheduleDeadline: @escaping @Sendable (WorldTimer) async throws -> Void,
        recordTurn: @escaping @Sendable (Scene, SceneTurn) async throws -> ConversationItemID,
        makeResponseID: @escaping @Sendable () -> ResponseID = { .generated() }
    ) {
        self.repository = repository
        self.clock = clock
        self.limits = limits
        self.performer = performer
        self.announce = announce
        self.scheduleDeadline = scheduleDeadline
        self.recordTurn = recordTurn
        self.makeResponseID = makeResponseID
    }

    /// Opens a scene and offers the floor to the first participant (the addressee, if any).
    /// Any scene already open in the region yields to the new one.
    public func open(
        sceneID: SceneID = .generated(),
        regionID: EntityID,
        conversationID: ConversationID,
        trigger: SceneTrigger,
        participants: [EntityID],
        trace: W3CTraceContext? = nil
    ) async throws -> Scene {
        try await withSpan("scene.open") { span in
            span.attributes["world.region_id"] = regionID.rawValue
            span.attributes["scene.participants"] = participants.count
            let now = WorldJSON.wireDate(await clock.now)
            for stale in try await repository.openScenes(in: regionID) {
                try await close(stale, reason: .interrupted, at: now)
            }
            var ordered = participants
            if let addressee = trigger.addresseeID, let index = ordered.firstIndex(of: addressee) {
                ordered.remove(at: index)
                ordered.insert(addressee, at: 0)
            }
            var scene = try Scene(
                sceneID: sceneID,
                regionID: regionID,
                conversationID: conversationID,
                trigger: trigger,
                participants: ordered,
                openedAt: now,
                trace: trace
            )
            span.attributes["scene.id"] = scene.sceneID.rawValue
            try await repository.save(scene)
            try await announce(
                makeEvent(
                    Self.openedEventType, scene: scene, at: now,
                    payload: [
                        "trigger": .string(trigger.text),
                        "participants": .array(ordered.map { .string($0.rawValue) }),
                    ]))
            await performer.sceneOpened(scene)
            try await offerFloor(&scene, to: ordered[0], at: now)
            return scene
        }
    }

    /// A character answers the offer: words, or a pass. Idempotent by `response_id`.
    public func submit(_ submission: SceneTurnSubmission, to sceneID: SceneID) async throws
        -> SceneTurnResult
    {
        try await withSpan("scene.turn") { span in
            span.attributes["scene.id"] = sceneID.rawValue
            span.attributes["agent.character_id"] = submission.characterID.rawValue
            guard var scene = try await repository.scene(id: sceneID) else {
                throw WorldContractError.invalidScene
            }
            if let recorded = scene.turns.first(where: { $0.responseID == submission.responseID }) {
                // The same answer again is a replay; a different answer to a floor that has
                // already been resolved (say, a late reply after the deadline passed) is not.
                let disposition: SceneTurnDisposition =
                    recorded.text == submission.text ? .duplicate : .notYourTurn
                span.attributes["scene.turn.disposition"] = disposition.rawValue
                return SceneTurnResult(disposition: disposition, scene: scene)
            }
            guard scene.state == .open, let floor = scene.floor,
                floor.characterID == submission.characterID,
                floor.responseID == submission.responseID
            else {
                span.attributes["scene.turn.disposition"] = "not_your_turn"
                return SceneTurnResult(disposition: .notYourTurn, scene: scene)
            }
            let now = WorldJSON.wireDate(await clock.now)
            try await take(&scene, floor: floor, text: submission.text, at: now)
            span.attributes["scene.turn.disposition"] = "accepted"
            span.attributes["scene.turn.pass"] = submission.text == nil
            let latest = try await repository.scene(id: sceneID) ?? scene
            return SceneTurnResult(disposition: .accepted, scene: latest)
        }
    }

    /// The floor's deadline passed without an answer: that is a pass.
    public func floorExpired(sceneID: SceneID, responseID: ResponseID) async throws {
        guard var scene = try await repository.scene(id: sceneID), scene.state == .open,
            let floor = scene.floor, floor.responseID == responseID
        else { return }
        try await take(&scene, floor: floor, text: nil, at: WorldJSON.wireDate(await clock.now))
    }

    public func scene(id: SceneID) async throws -> Scene? {
        try await repository.scene(id: id)
    }

    public func recentScenes(limit: Int = 50) async throws -> [Scene] {
        try await repository.recentScenes(limit: limit)
    }

    // MARK: - The floor

    private func take(
        _ scene: inout Scene, floor: SceneFloor, text: String?, at now: Date
    ) async throws {
        var turn = SceneTurn(
            characterID: floor.characterID,
            responseID: floor.responseID,
            text: text,
            offeredAt: floor.offeredAt,
            answeredAt: now
        )
        if text != nil {
            turn.conversationItemID = try await recordTurn(scene, turn)
        }
        scene.turns.append(turn)
        scene.floor = nil
        try await repository.save(scene)
        if text != nil {
            await performer.sceneTurn(scene, turn)
        }
        try await announce(
            makeEvent(
                Self.turnEventType, scene: scene, at: now,
                subject: floor.characterID,
                payload: [
                    "character_id": .string(floor.characterID.rawValue),
                    "response_id": .string(floor.responseID.rawValue),
                    "pass": .bool(text == nil),
                    "text": text.map { .string($0) } ?? .null,
                ]))

        if let reason = closeReason(for: scene) {
            try await close(scene, reason: reason, at: now)
            return
        }
        let next = nextParticipant(after: floor.characterID, in: scene)
        try await offerFloor(&scene, to: next, at: now)
    }

    private func offerFloor(_ scene: inout Scene, to characterID: EntityID, at now: Date)
        async throws
    {
        let responseID = makeResponseID()
        let floor = SceneFloor(
            characterID: characterID,
            responseID: responseID,
            offeredAt: now,
            deadline: now.addingTimeInterval(limits.floorSeconds)
        )
        scene.floor = floor
        try await repository.save(scene)
        let offer = SceneTurnOffer(
            sceneID: scene.sceneID,
            characterID: characterID,
            responseID: responseID,
            deadline: floor.deadline,
            trigger: scene.trigger,
            participants: scene.participants,
            turns: scene.turns
        )
        try await announce(
            WorldEventEnvelope(
                occurredAt: now,
                source: EventSource(
                    id: Self.sourceID, kind: "world",
                    sourceEventID: "\(scene.sceneID.rawValue):\(responseID.rawValue)"),
                subjectIDs: [characterID, scene.regionID],
                placeID: scene.regionID,
                epistemic: EpistemicState(type: .observed, confidence: 1),
                payload: offer,
                causedBy: [.event(scene.trigger.eventID)],
                trace: scene.trace
            ))
        try await scheduleDeadline(
            WorldTimer(
                timerID: try TimerID(validating: "timer:scene-floor:\(responseID.rawValue)"),
                purpose: Self.floorExpiredEventType,
                dueAt: floor.deadline,
                status: .pending,
                subjectIDs: [characterID, scene.regionID],
                causedBy: [.event(scene.trigger.eventID)],
                payload: [
                    "scene_id": .string(scene.sceneID.rawValue),
                    "response_id": .string(responseID.rawValue),
                ]
            ))
    }

    private func nextParticipant(after characterID: EntityID, in scene: Scene) -> EntityID {
        guard let index = scene.participants.firstIndex(of: characterID) else {
            return scene.participants[0]
        }
        return scene.participants[(index + 1) % scene.participants.count]
    }

    /// The cutoffs: everyone passed in a row, too many turns, or too much to say.
    private func closeReason(for scene: Scene) -> SceneCloseReason? {
        let count = scene.participants.count
        if scene.turns.count >= count, scene.turns.suffix(count).allSatisfy(\.isPass) {
            return .everyonePassed
        }
        if scene.turns.count >= limits.maximumTurns {
            return .maximumTurns
        }
        let spoken = scene.spokenTurns.reduce(0.0) { $0 + limits.spokenSeconds(of: $1.text ?? "") }
        if spoken >= limits.maximumSpokenSeconds {
            return .maximumSpokenSeconds
        }
        return nil
    }

    // MARK: - Closing and performing

    private func close(_ closing: Scene, reason: SceneCloseReason, at now: Date) async throws {
        var scene = closing
        scene.floor = nil
        scene.closeReason = reason
        scene.closedAt = now
        scene.state = scene.spokenTurns.isEmpty ? .abandoned : .rendering
        try await repository.save(scene)
        try await announce(
            makeEvent(
                Self.closedEventType, scene: scene, at: now,
                payload: [
                    "reason": .string(reason.rawValue),
                    "spoken_turns": .number(Double(scene.spokenTurns.count)),
                ]))
        guard scene.state == .rendering else { return }
        try await perform(scene)
    }

    private func perform(_ rendering: Scene) async throws {
        var scene = rendering
        let performance: ScenePerformance
        do {
            performance = try await performer.sceneClosed(scene)
        } catch {
            performance = ScenePerformance(
                state: .failed,
                errorCode: "scene_performance_failed",
                occurredAt: await clock.now
            )
        }
        scene.performance = performance
        scene.state = performance.state == .failed ? .abandoned : .performed
        try await repository.save(scene)
        try await announce(
            makeEvent(
                Self.performedEventType, scene: scene, at: performance.occurredAt,
                payload: [
                    "state": .string(performance.state.rawValue),
                    "provider_reference": performance.providerReference.map { .string($0) }
                        ?? .null,
                    "error_code": performance.errorCode.map { .string($0) } ?? .null,
                ]))
    }

    private func makeEvent(
        _ type: WorldEventType,
        scene: Scene,
        at now: Date,
        subject: EntityID? = nil,
        payload: [String: WorldJSONValue]
    ) throws -> WorldEventEnvelope {
        var payload = payload
        payload["scene_id"] = .string(scene.sceneID.rawValue)
        payload["state"] = payload["state"] ?? .string(scene.state.rawValue)
        return try WorldEventEnvelope(
            type: type,
            occurredAt: now,
            source: EventSource(
                id: Self.sourceID, kind: "world",
                sourceEventID: "\(scene.sceneID.rawValue):\(type.rawValue):\(scene.turns.count)"),
            subjectIDs: [subject ?? scene.regionID] + scene.participants,
            placeID: scene.regionID,
            epistemic: EpistemicState(type: .observed, confidence: 1),
            payload: payload,
            causedBy: [.event(scene.trigger.eventID)],
            trace: scene.trace
        )
    }
}
