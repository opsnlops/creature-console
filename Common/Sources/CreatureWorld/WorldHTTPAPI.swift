import Foundation
import HTTPTypes
import Hummingbird
import ServiceLifecycle
import WorldCore

struct WorldHTTPAPI: Sendable {
    let configuration: CreatureWorldConfiguration
    let service: any WorldApplicationService
    let conversationService: any ConversationApplicationService
    let characterSessionService: any CharacterSessionApplicationService
    let sceneService: any SceneApplicationService
    let limits: WorldAPIConfiguration
    let concurrencyLimiter: WorldAPIConcurrencyLimiter

    init(
        configuration: CreatureWorldConfiguration,
        service: any WorldApplicationService,
        conversationService: any ConversationApplicationService,
        characterSessionService: any CharacterSessionApplicationService =
            UnavailableCharacterSessionApplicationService(),
        sceneService: any SceneApplicationService = UnavailableSceneApplicationService(),
        limits: WorldAPIConfiguration = .default
    ) {
        self.configuration = configuration
        self.service = service
        self.conversationService = conversationService
        self.characterSessionService = characterSessionService
        self.sceneService = sceneService
        self.limits = limits
        self.concurrencyLimiter = WorldAPIConcurrencyLimiter(
            limit: limits.maximumConcurrentRequests
        )
    }

    func addRoutes(to router: RouterGroup<BasicRequestContext>) {
        router.post("v1/conversations/:conversationID/utterances") { request, context in
            await respond {
                try requireJSON(request)
                guard let rawConversationID = context.parameters.get("conversationID") else {
                    throw WorldAPIError.invalidQuery(name: "conversation_id")
                }
                let conversationID = try ConversationID(validating: rawConversationID)
                return try await execute {
                    var utterance = try await decode(
                        PersonUtterance.self,
                        from: request,
                        maximumBytes: limits.maximumBodyBytes
                    )
                    guard utterance.conversationID == conversationID else {
                        throw WorldAPIError.conversationIdentityMismatch
                    }
                    // April's words arrive under the gateway's trace; carrying it on the
                    // utterance lets the percept, the mind, and Beaky's reply all join it.
                    if utterance.trace == nil {
                        utterance.trace = try traceContext(from: request)
                    }
                    let result = try await conversationService.ingest(utterance)
                    let status: HTTPResponse.Status =
                        result.disposition == .accepted ? .accepted : .ok
                    return try jsonResponse(result, status: status)
                }
            }
        }

        router.post("v1/conversations/:conversationID/responses") { request, context in
            await respond {
                try requireJSON(request)
                guard let rawConversationID = context.parameters.get("conversationID") else {
                    throw WorldAPIError.invalidQuery(name: "conversation_id")
                }
                let conversationID = try ConversationID(validating: rawConversationID)
                return try await execute {
                    var intent = try await decode(
                        CharacterUtteranceIntent.self,
                        from: request,
                        maximumBytes: limits.maximumBodyBytes
                    )
                    guard intent.conversationID == conversationID else {
                        throw WorldAPIError.conversationIdentityMismatch
                    }
                    if intent.trace == nil {
                        intent.trace = try traceContext(from: request)
                    }
                    let result = try await conversationService.respond(intent)
                    let status: HTTPResponse.Status =
                        result.disposition == .accepted ? .accepted : .ok
                    return try jsonResponse(result, status: status)
                }
            }
        }

        router.post("v1/conversations/:conversationID/stage") { request, context in
            await respond {
                try requireJSON(request)
                guard let rawConversationID = context.parameters.get("conversationID") else {
                    throw WorldAPIError.invalidQuery(name: "conversation_id")
                }
                let conversationID = try ConversationID(validating: rawConversationID)
                return try await execute {
                    let stageRequest = try await decode(
                        CharacterStageRequest.self,
                        from: request,
                        maximumBytes: limits.maximumBodyBytes
                    )
                    return try jsonResponse(
                        await conversationService.stage(stageRequest, in: conversationID),
                        status: .ok
                    )
                }
            }
        }

        router.post("v1/conversations/:conversationID/performances") { request, context in
            await respond {
                try requireJSON(request)
                guard let rawConversationID = context.parameters.get("conversationID") else {
                    throw WorldAPIError.invalidQuery(name: "conversation_id")
                }
                let conversationID = try ConversationID(validating: rawConversationID)
                return try await execute {
                    var performance = try await decode(
                        CharacterPerformance.self,
                        from: request,
                        maximumBytes: limits.maximumBodyBytes
                    )
                    guard performance.intent.conversationID == conversationID else {
                        throw WorldAPIError.conversationIdentityMismatch
                    }
                    if performance.intent.trace == nil {
                        performance.intent.trace = try traceContext(from: request)
                    }
                    let result = try await conversationService.perform(
                        performance, in: conversationID)
                    let status: HTTPResponse.Status =
                        result.disposition == .accepted ? .accepted : .ok
                    return try jsonResponse(result, status: status)
                }
            }
        }

        router.post("v1/characters/:characterID/login") { request, context in
            await respond {
                try requireJSON(request)
                let characterID = try characterID(from: context)
                return try await execute {
                    let login = try await decode(
                        CharacterLoginRequest.self, from: request,
                        maximumBytes: limits.maximumBodyBytes)
                    let result = try await characterSessionService.login(characterID, login)
                    return try jsonResponse(
                        result,
                        status: result.disposition == .loggedInElsewhere ? .conflict : .ok
                    )
                }
            }
        }

        router.post("v1/characters/:characterID/heartbeat") { request, context in
            await respond {
                try requireJSON(request)
                let characterID = try characterID(from: context)
                return try await execute {
                    let reference = try await decode(
                        CharacterSessionReference.self, from: request,
                        maximumBytes: limits.maximumBodyBytes)
                    return try jsonResponse(
                        await characterSessionService.heartbeat(characterID, reference),
                        status: .ok)
                }
            }
        }

        router.post("v1/characters/:characterID/logout") { request, context in
            await respond {
                try requireJSON(request)
                let characterID = try characterID(from: context)
                return try await execute {
                    let reference = try await decode(
                        CharacterSessionReference.self, from: request,
                        maximumBytes: limits.maximumBodyBytes)
                    return try jsonResponse(
                        await characterSessionService.logout(characterID, reference),
                        status: .ok)
                }
            }
        }

        router.get("v1/characters") { _, _ in
            await respond {
                try await execute {
                    try jsonResponse(
                        CharacterSessionPage(
                            sessions: await characterSessionService.characterSessions()),
                        status: .ok)
                }
            }
        }

        router.post("v1/scenes/:sceneID/turns") { request, context in
            await respond {
                try requireJSON(request)
                let sceneID = try sceneID(from: context)
                return try await execute {
                    var submission = try await decode(
                        SceneTurnSubmission.self, from: request,
                        maximumBytes: limits.maximumBodyBytes)
                    if submission.trace == nil {
                        submission.trace = try traceContext(from: request)
                    }
                    let result = try await sceneService.submitSceneTurn(submission, to: sceneID)
                    let status: HTTPResponse.Status =
                        switch result.disposition {
                        case .accepted: .accepted
                        case .duplicate: .ok
                        case .notYourTurn: .conflict
                        }
                    return try jsonResponse(result, status: status)
                }
            }
        }

        router.get("v1/scenes/:sceneID") { _, context in
            await respond {
                let sceneID = try sceneID(from: context)
                return try await execute {
                    guard let scene = try await sceneService.scene(id: sceneID) else {
                        return try jsonResponse(
                            WorldAPIErrorResponse(error: "not_found", message: "No such scene"),
                            status: .notFound)
                    }
                    return try jsonResponse(scene, status: .ok)
                }
            }
        }

        router.get("v1/scenes") { request, _ in
            await respond {
                let limit = try pageLimit(request)
                return try await execute {
                    try jsonResponse(
                        ScenePage(scenes: await sceneService.recentScenes(limit: limit)),
                        status: .ok)
                }
            }
        }

        router.get("v1/conversations/:conversationID/items") { request, context in
            await respond {
                guard let rawConversationID = context.parameters.get("conversationID") else {
                    throw WorldAPIError.invalidQuery(name: "conversation_id")
                }
                let conversationID = try ConversationID(validating: rawConversationID)
                let after = try request.uri.queryParameters["after_item_id"].map {
                    try ConversationItemID(validating: String($0))
                }
                let limit = try pageLimit(request)
                return try await execute {
                    try jsonResponse(
                        await conversationService.conversationItems(
                            in: conversationID,
                            after: after,
                            limit: limit
                        )
                    )
                }
            }
        }

        router.get("v1/conversations/:conversationID/deliveries") { request, context in
            await respond {
                guard let rawConversationID = context.parameters.get("conversationID") else {
                    throw WorldAPIError.invalidQuery(name: "conversation_id")
                }
                let conversationID = try ConversationID(validating: rawConversationID)
                let after = try request.uri.queryParameters["after_response_id"].map {
                    try ResponseID(validating: String($0))
                }
                let limit = try pageLimit(request)
                return try await execute {
                    try jsonResponse(
                        await conversationService.deliveries(
                            in: conversationID,
                            after: after,
                            limit: limit
                        )
                    )
                }
            }
        }

        router.get("v1/conversations/:conversationID/stream") { request, context in
            await respond {
                try validateOrigin(request)
                guard let rawConversationID = context.parameters.get("conversationID") else {
                    throw WorldAPIError.invalidQuery(name: "conversation_id")
                }
                let conversationID = try ConversationID(validating: rawConversationID)
                let stream = try await execute {
                    try await conversationService.subscribe(to: conversationID)
                }
                var headers: HTTPFields = [
                    .contentType: "text/event-stream; charset=utf-8",
                    .cacheControl: "no-cache",
                ]
                headers[HTTPField.Name("x-accel-buffering")!] = "no"
                return Response(
                    status: .ok,
                    headers: headers,
                    body: ResponseBody { writer in
                        await withGracefulShutdownHandler {
                            await writeConversationStream(
                                conversationID: conversationID,
                                stream: stream,
                                writer: &writer
                            )
                        } onGracefulShutdown: {
                            Task {
                                await conversationService.finishConversationSubscriptions()
                            }
                        }
                    }
                )
            }
        }

        router.post("v1/events") { request, _ in
            await respond {
                try requireJSON(request)
                return try await execute {
                    var event = try await decode(
                        WorldEventEnvelope.self,
                        from: request,
                        maximumBytes: limits.maximumBodyBytes
                    )
                    try applyTraceHeaders(from: request, to: &event)
                    let acceptance = try await service.accept(event)
                    let status: HTTPResponse.Status =
                        acceptance.disposition == .accepted ? .accepted : .ok
                    return try jsonResponse(
                        WorldEventAcceptanceResponse(acceptance),
                        status: status
                    )
                }
            }
        }

        router.post("v1/events:batch") { request, _ in
            await respond {
                try requireJSON(request)
                return try await execute {
                    let batch = try await decode(
                        WorldEventBatchRequest.self,
                        from: request,
                        maximumBytes: limits.maximumBodyBytes
                    )
                    guard batch.events.count <= limits.maximumBatchSize else {
                        throw WorldAPIError.batchTooLarge(limit: limits.maximumBatchSize)
                    }
                    var results: [WorldEventAcceptanceResponse] = []
                    results.reserveCapacity(batch.events.count)
                    for proposedEvent in batch.events {
                        var event = proposedEvent
                        try applyTraceHeaders(from: request, to: &event)
                        results.append(
                            WorldEventAcceptanceResponse(try await service.accept(event))
                        )
                    }
                    return try jsonResponse(WorldEventBatchResponse(results: results))
                }
            }
        }

        router.get("v1/events") { request, _ in
            await respond {
                let afterSequence = try nonnegativeInt64Query(
                    "after_sequence",
                    request: request,
                    default: 0
                )
                let limit = try pageLimit(request)
                return try await execute {
                    try jsonResponse(
                        await service.events(after: afterSequence, limit: limit)
                    )
                }
            }
        }

        router.get("v1/facts") { request, _ in
            await respond {
                let subjectID = try request.uri.queryParameters["subject_id"].map {
                    try EntityID(validating: String($0))
                }
                let after = try request.uri.queryParameters["after_fact_id"].map {
                    try FactID(validating: String($0))
                }
                let limit = try pageLimit(request)
                return try await execute {
                    try jsonResponse(
                        await service.currentFacts(
                            subjectID: subjectID,
                            after: after,
                            limit: limit
                        )
                    )
                }
            }
        }

        router.get("v1/timers") { request, _ in
            await respond {
                let status = try request.uri.queryParameters["status"].map {
                    guard let status = WorldTimerStatus(rawValue: String($0)) else {
                        throw WorldAPIError.invalidQuery(name: "status")
                    }
                    return status
                }
                let after = try request.uri.queryParameters["after_timer_id"].map {
                    try TimerID(validating: String($0))
                }
                let limit = try pageLimit(request)
                return try await execute {
                    try jsonResponse(
                        await service.timers(status: status, after: after, limit: limit)
                    )
                }
            }
        }

        router.get("v1/snapshot") { request, _ in
            await respond {
                let limit = try pageLimit(request)
                return try await execute {
                    try jsonResponse(await service.snapshot(limit: limit))
                }
            }
        }

        router.get("v1/stream") { request, _ in
            await respond {
                try validateOrigin(request)
                let querySequence = try request.uri.queryParameters["after_sequence"].map {
                    guard let value = Int64($0), value >= 0 else {
                        throw WorldAPIError.invalidQuery(name: "after_sequence")
                    }
                    return value
                }
                let lastEventSequence = try header("last-event-id", from: request).map {
                    guard let value = Int64($0), value >= 0 else {
                        throw WorldAPIError.invalidQuery(name: "Last-Event-ID")
                    }
                    return value
                }
                let afterSequence = querySequence ?? lastEventSequence
                let service = self.service
                let stream = try await execute { try await service.subscribe() }
                let maximumPageSize = limits.maximumPageSize
                return Response(
                    status: .ok,
                    headers: [
                        .contentType: "text/event-stream; charset=utf-8",
                        .cacheControl: "no-cache",
                    ],
                    body: ResponseBody { writer in
                        await withGracefulShutdownHandler {
                            await writeEventStream(
                                afterSequence: afterSequence,
                                stream: stream,
                                maximumPageSize: maximumPageSize,
                                service: service,
                                writer: &writer
                            )
                        } onGracefulShutdown: {
                            Task {
                                await service.finishSubscriptions()
                            }
                        }
                    }
                )
            }
        }
    }

    private func validateOrigin(_ request: Request) throws {
        guard let origin = request.headers[.origin] else { return }
        guard configuration.allowedOrigins.contains(String(origin)) else {
            throw WorldAPIError.invalidOrigin
        }
    }

    private func requireJSON(_ request: Request) throws {
        guard let contentType = request.headers[.contentType],
            contentType.split(separator: ";", maxSplits: 1)[0]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() == "application/json"
        else {
            throw WorldAPIError.unsupportedMediaType
        }
    }

    private func pageLimit(_ request: Request) throws -> Int {
        guard let rawLimit = request.uri.queryParameters["limit"] else {
            return limits.defaultPageSize
        }
        guard let limit = Int(rawLimit), (1...limits.maximumPageSize).contains(limit) else {
            throw WorldAPIError.invalidQuery(name: "limit")
        }
        return limit
    }

    private func nonnegativeInt64Query(
        _ name: String,
        request: Request,
        default defaultValue: Int64
    ) throws -> Int64 {
        guard let rawValue = request.uri.queryParameters[Substring(name)] else {
            return defaultValue
        }
        guard let value = Int64(rawValue), value >= 0 else {
            throw WorldAPIError.invalidQuery(name: name)
        }
        return value
    }

    private func decode<Value: Decodable>(
        _ type: Value.Type,
        from request: Request,
        maximumBytes: Int
    ) async throws -> Value {
        let buffer = try await request.body.collect(upTo: maximumBytes)
        return try WorldJSON.makeDecoder().decode(type, from: buffer)
    }

    private func applyTraceHeaders(
        from request: Request,
        to event: inout WorldEventEnvelope
    ) throws {
        guard event.trace == nil else { return }
        event.trace = try traceContext(from: request)
    }

    private func traceContext(from request: Request) throws -> W3CTraceContext? {
        guard let traceparent = header("traceparent", from: request) else { return nil }
        return try W3CTraceContext(
            traceparent: traceparent,
            tracestate: header("tracestate", from: request),
            baggage: header("baggage", from: request)
        )
    }

    private func sceneID(from context: BasicRequestContext) throws -> SceneID {
        guard let raw = context.parameters.get("sceneID") else {
            throw WorldAPIError.invalidQuery(name: "scene_id")
        }
        return try SceneID(validating: raw)
    }

    private func characterID(from context: BasicRequestContext) throws -> EntityID {
        guard let raw = context.parameters.get("characterID") else {
            throw WorldAPIError.invalidQuery(name: "character_id")
        }
        return try EntityID(validating: raw)
    }

    private func header(_ name: String, from request: Request) -> String? {
        request.headers.first { $0.name.canonicalName == name }?.value
    }

    private func respond(
        _ operation: () async throws -> Response
    ) async -> Response {
        do {
            return try await operation()
        } catch {
            return (try? errorResponse(for: error))
                ?? Response(status: .internalServerError)
        }
    }

    private func execute<Value: Sendable>(
        _ operation: @Sendable @escaping () async throws -> Value
    ) async throws -> Value {
        try await concurrencyLimiter.withPermit {
            try await withThrowingTaskGroup(of: Value.self) { group in
                group.addTask {
                    try await operation()
                }
                group.addTask {
                    try await Task.sleep(for: limits.maximumRequestDuration)
                    throw WorldAPIError.requestTimedOut
                }
                guard let result = try await group.next() else {
                    throw WorldAPIError.requestTimedOut
                }
                group.cancelAll()
                return result
            }
        }
    }

    private func errorResponse(for error: any Error) throws -> Response {
        let status: HTTPResponse.Status
        let code: String
        switch error {
        case WorldAPIError.invalidOrigin:
            status = .forbidden
            code = "origin_not_allowed"
        case WorldAPIError.unsupportedMediaType:
            status = .unsupportedMediaType
            code = "unsupported_media_type"
        case WorldAPIError.invalidQuery:
            status = .badRequest
            code = "invalid_query"
        case WorldAPIError.conversationIdentityMismatch:
            status = .conflict
            code = "conversation_identity_mismatch"
        case WorldAPIError.batchTooLarge:
            status = .contentTooLarge
            code = "batch_too_large"
        case WorldAPIError.overloaded, WorldProcessingError.queueFull,
            WorldSubscriptionError.subscriptionLimitReached:
            status = .serviceUnavailable
            code = "overloaded"
        case WorldAPIError.requestTimedOut:
            status = .gatewayTimeout
            code = "request_timeout"
        case WorldAPIError.databaseUnavailable,
            MongoWorldPersistenceProviderError.unavailable:
            status = .serviceUnavailable
            code = "persistence_unavailable"
        case let responseError as any HTTPResponseError
        where responseError.status == .contentTooLarge:
            status = .contentTooLarge
            code = "body_too_large"
        case WorldContractError.characterSessionNotLive:
            status = .conflict
            code = "logged_in_elsewhere"
        case is DecodingError, is WorldContractError, is WorldIdentifierError:
            status = .badRequest
            code = "invalid_request"
        default:
            status = .internalServerError
            code = "internal_error"
        }
        let message =
            status == .internalServerError
            ? "Creature World could not complete the request"
            : error.localizedDescription
        return try jsonResponse(
            WorldAPIErrorResponse(error: code, message: message),
            status: status
        )
    }

    private func jsonResponse<Value: Encodable>(
        _ value: Value,
        status: HTTPResponse.Status = .ok
    ) throws -> Response {
        let data = try WorldJSON.makeEncoder().encode(value)
        return Response(
            status: status,
            headers: [.contentType: "application/json; charset=utf-8"],
            body: ResponseBody(byteBuffer: ByteBuffer(bytes: data))
        )
    }

    private func writeSSE<Value: Encodable>(
        event: String,
        id: String?,
        value: Value,
        writer: inout any ResponseBodyWriter
    ) async throws {
        let data = try WorldJSON.makeEncoder().encode(value)
        var message = "event: \(event)\n"
        if let id {
            message += "id: \(id)\n"
        }
        message += "data: \(String(decoding: data, as: UTF8.self))\n\n"
        try await writer.write(ByteBuffer(string: message))
    }

    private func writeEventStream(
        afterSequence: Int64?,
        stream: WorldDeltaStream,
        maximumPageSize: Int,
        service: any WorldApplicationService,
        writer: inout any ResponseBodyWriter
    ) async {
        var lastSequence = afterSequence ?? 0
        do {
            if afterSequence == nil {
                let snapshot = try await execute {
                    try await service.snapshot(limit: maximumPageSize)
                }
                try await writeSSE(
                    event: "snapshot",
                    id: String(snapshot.latestSequence),
                    value: snapshot,
                    writer: &writer
                )
                lastSequence = snapshot.latestSequence
            } else {
                var hasMore = true
                while hasMore {
                    let querySequence = lastSequence
                    let page = try await execute {
                        try await service.events(after: querySequence, limit: maximumPageSize)
                    }
                    for event in page.events {
                        try await writeSSE(
                            event: "event",
                            id: event.worldSequence.map(String.init),
                            value: event,
                            writer: &writer
                        )
                    }
                    lastSequence = page.nextSequence
                    hasMore = page.hasMore
                }
            }

            for try await delta in stream {
                guard let sequence = delta.event.worldSequence, sequence > lastSequence else {
                    continue
                }
                try await writeSSE(
                    event: "delta",
                    id: String(sequence),
                    value: delta,
                    writer: &writer
                )
                lastSequence = sequence
            }
        } catch {
            try? await writeSSE(
                event: "resnapshot_required",
                id: nil,
                value: WorldAPIErrorResponse(
                    error: "stream_unavailable",
                    message: "Reconnect without after_sequence to fetch a new snapshot"
                ),
                writer: &writer
            )
        }
        try? await writer.finish(nil)
    }

    private func writeConversationStream(
        conversationID: ConversationID,
        stream: ConversationItemStream,
        writer: inout any ResponseBodyWriter
    ) async {
        do {
            try await writeSSE(
                event: "ready",
                id: nil,
                value: ConversationStreamReady(conversationID: conversationID),
                writer: &writer
            )
            for await update in stream {
                switch update {
                case .item(let item):
                    try await writeSSE(
                        event: "item",
                        id: item.itemID.rawValue,
                        value: item,
                        writer: &writer
                    )
                case .heartbeat:
                    try await writer.write(ByteBuffer(string: ": keep-alive\n\n"))
                }
            }
        } catch {
            // The stream's termination removes its broker subscription.
        }
        try? await writer.finish(nil)
    }

}

private struct ConversationStreamReady: Encodable {
    let conversationID: ConversationID

    private enum CodingKeys: String, CodingKey {
        case conversationID = "conversation_id"
    }
}
