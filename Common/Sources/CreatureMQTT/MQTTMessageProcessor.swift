import ArgumentParser
import Common
import Foundation
import Logging
import NIOConcurrencyHelpers

/// A `MessageProcessor` that republishes websocket events to MQTT using scalar attributes.
final class MQTTMessageProcessor: MessageProcessor {

    enum MessageType: String, CaseIterable, ExpressibleByArgument {
        case boardSensors = "board-sensors"
        case cacheInvalidation = "cache-invalidation"
        case emergencyStop = "emergency-stop"
        case idleStateChanged = "idle-state-changed"
        case log = "log"
        case motorSensors = "motor-sensors"
        case notice = "notice"
        case playlistStatus = "playlist-status"
        case statusLights = "status-lights"
        case systemCounters = "system-counters"
        case creatureActivity = "creature-activity"
        case watchdogWarning = "watchdog-warning"
        case jobProgress = "job-progress"
        case jobComplete = "job-complete"

        static var helpText: String {
            Self.allCases.map { $0.rawValue }.sorted().joined(separator: ", ")
        }
    }

    private let mqttClient: MQTTClientManager
    private let hiddenTypes: Set<MessageType>
    private let allowedTypes: Set<MessageType>?
    private let logger: Logger
    private let nameResolver: CreatureNameResolver
    private let fetchCreatureName: @Sendable (CreatureIdentifier) async -> String?
    private let animationNameResolver: AnimationNameResolver
    private let fetchAnimationName: @Sendable (AnimationIdentifier) async -> String?
    private let reloadAnimationNames: @Sendable () async -> [AnimationIdentifier: String]
    private let lastPublished: NIOLockedValueBox<[String: String]>
    private let retainMessages: Bool

    init(
        mqttClient: MQTTClientManager,
        hiddenTypes: Set<MessageType> = [],
        allowedTypes: Set<MessageType>? = nil,
        logLevel: Logger.Level,
        nameResolver: CreatureNameResolver,
        fetchCreatureName: @escaping @Sendable (CreatureIdentifier) async -> String?,
        animationNameResolver: AnimationNameResolver,
        fetchAnimationName: @escaping @Sendable (AnimationIdentifier) async -> String?,
        reloadAnimationNames: @escaping @Sendable () async -> [AnimationIdentifier: String],
        retainMessages: Bool
    ) {
        self.mqttClient = mqttClient
        self.hiddenTypes = hiddenTypes
        self.allowedTypes = allowedTypes
        self.nameResolver = nameResolver
        self.fetchCreatureName = fetchCreatureName
        self.animationNameResolver = animationNameResolver
        self.fetchAnimationName = fetchAnimationName
        self.reloadAnimationNames = reloadAnimationNames
        self.lastPublished = NIOLockedValueBox([:])
        self.retainMessages = retainMessages

        var logger = Logger(label: "io.opsnlops.creature-mqtt.processor")
        logger.logLevel = logLevel
        self.logger = logger
    }

    private func shouldPublish(_ type: MessageType) -> Bool {
        if let allowedTypes, !allowedTypes.contains(type) {
            return false
        }
        return !hiddenTypes.contains(type)
    }

    private func publishValue(
        _ value: String,
        components: [String],
        retain: Bool? = nil
    ) {
        let mqttClient = mqttClient
        let logger = logger
        let cache = lastPublished
        let retainFlag = retain ?? retainMessages
        Task { @Sendable [value, components, mqttClient, logger, cache, retainFlag] in
            let topic = await mqttClient.topicString(for: components)
            let alreadyPublished = cache.withLockedValue { store in store[topic] == value }
            guard !alreadyPublished else { return }

            do {
                try await mqttClient.publishString(
                    value, components: components, retain: retainFlag)
                cache.withLockedValue { store in store[topic] = value }
            } catch {
                logger.error("Failed to publish \(topic) to MQTT: \(error.localizedDescription)")
            }
        }
    }

    private func publishBool(_ value: Bool, components: [String]) {
        publishValue(value ? "true" : "false", components: components)
    }

    private func publishNumber<T: LosslessStringConvertible>(_ value: T, components: [String]) {
        publishValue(String(value), components: components)
    }

    private func publishDate(_ date: Date, components: [String]) {
        publishValue(ISO8601DateFormatter().string(from: date), components: components)
    }

    private func resolveCreature(
        id: CreatureIdentifier,
        preferredName: String? = nil
    ) -> (topicComponent: String, resolvedName: String?) {
        nameResolver.resolve(
            id: id, preferredName: preferredName, fetchIfMissing: fetchCreatureName)
    }

    private func publishIdentity(
        topicComponent: String,
        id: CreatureIdentifier,
        name: String?
    ) {
        publishValue(id, components: [topicComponent, "id"], retain: retainMessages)
        if let name, !name.isEmpty {
            publishValue(name, components: [topicComponent, "name"], retain: retainMessages)
        }
    }

    func processBoardSensorReport(_ boardSensorReport: BoardSensorReport) {
        guard shouldPublish(.boardSensors) else { return }
        let resolved = resolveCreature(id: boardSensorReport.creatureId)
        let base = [resolved.topicComponent, "sensors", "board"]
        publishIdentity(
            topicComponent: resolved.topicComponent, id: boardSensorReport.creatureId,
            name: resolved.resolvedName)
        publishNumber(boardSensorReport.boardTemperature, components: base + ["temperature_f"])
        publishDate(boardSensorReport.timestamp, components: base + ["timestamp"])

        for powerReport in boardSensorReport.powerReports {
            let powerBase = base + ["power", powerReport.name]
            publishNumber(powerReport.voltage, components: powerBase + ["voltage"])
            publishNumber(powerReport.current, components: powerBase + ["current"])
            publishNumber(powerReport.power, components: powerBase + ["power"])
        }
    }

    func processCacheInvalidation(_ cacheInvalidation: CacheInvalidation) {
        if shouldPublish(.cacheInvalidation) {
            let base = ["cache_invalidation"]
            publishValue(cacheInvalidation.cacheType.description, components: base + ["cache_type"])
            publishDate(.now, components: base + ["timestamp"])
        }

        switch cacheInvalidation.cacheType {
        case .animation, .adHocAnimationList:
            Task { [animationNameResolver, reloadAnimationNames] in
                let names = await reloadAnimationNames()
                animationNameResolver.replaceAll(names)
            }
        default:
            break
        }
    }

    func processEmergencyStop(_ emergencyStop: EmergencyStop) {
        guard shouldPublish(.emergencyStop) else { return }
        let base = ["events", "emergency_stop"]
        publishValue(emergencyStop.reason, components: base + ["reason"])
        publishDate(emergencyStop.timestamp, components: base + ["timestamp"])
    }

    func processLog(_ logItem: ServerLogItem) {
        guard shouldPublish(.log) else { return }
        let base = ["logs"]
        publishDate(logItem.timestamp, components: base + ["timestamp"])
        publishValue(logItem.level, components: base + ["level"])
        publishValue(logItem.message, components: base + ["message"])
        publishValue(logItem.logger_name, components: base + ["logger_name"])
        publishNumber(logItem.thread_id, components: base + ["thread_id"])
    }

    func processMotorSensorReport(_ motorSensorReport: MotorSensorReport) {
        guard shouldPublish(.motorSensors) else { return }
        let resolved = resolveCreature(id: motorSensorReport.creatureId)
        let base = [resolved.topicComponent, "sensors", "motors"]
        publishIdentity(
            topicComponent: resolved.topicComponent, id: motorSensorReport.creatureId,
            name: resolved.resolvedName)
        publishDate(motorSensorReport.timestamp, components: base + ["timestamp"])
        for motor in motorSensorReport.motors {
            let motorBase = base + ["\(motor.motorNumber)"]
            publishNumber(motor.position, components: motorBase + ["position"])
            publishNumber(motor.current, components: motorBase + ["current"])
            publishNumber(motor.power, components: motorBase + ["power"])
            publishNumber(motor.voltage, components: motorBase + ["voltage"])
        }
    }

    func processNotice(_ notice: Notice) {
        guard shouldPublish(.notice) else { return }
        let base = ["notices", "latest"]
        publishValue(notice.message, components: base + ["message"])
        publishDate(notice.timestamp, components: base + ["timestamp"])
    }

    func processPlaylistStatus(_ playlistStatus: PlaylistStatus) {
        guard shouldPublish(.playlistStatus) else { return }
        let base = ["playlists", playlistStatus.playlist]
        publishBool(playlistStatus.playing, components: base + ["playing"])
        publishValue(playlistStatus.currentAnimation, components: base + ["current_animation"])
        publishNumber(playlistStatus.universe, components: base + ["universe"])
        publishDate(.now, components: base + ["timestamp"])
    }

    func processStatusLights(_ statusLights: VirtualStatusLightsDTO) {
        guard shouldPublish(.statusLights) else { return }
        let base = ["status_lights"]
        publishBool(statusLights.running, components: base + ["running"])
        publishBool(statusLights.dmx, components: base + ["dmx"])
        publishBool(statusLights.streaming, components: base + ["streaming"])
        publishBool(statusLights.animation_playing, components: base + ["animation_playing"])
        publishDate(.now, components: base + ["timestamp"])
    }

    func processSystemCounters(_ counters: ServerCountersPayload) {
        guard shouldPublish(.systemCounters) else { return }
        let countersBase = ["system", "counters"]
        publishNumber(counters.counters.totalFrames, components: countersBase + ["total_frames"])
        publishNumber(
            counters.counters.eventsProcessed, components: countersBase + ["events_processed"])
        publishNumber(
            counters.counters.framesStreamed, components: countersBase + ["frames_streamed"])
        publishNumber(
            counters.counters.dmxEventsProcessed,
            components: countersBase + ["dmx_events_processed"])
        publishNumber(
            counters.counters.animationsPlayed, components: countersBase + ["animations_played"])
        publishNumber(counters.counters.soundsPlayed, components: countersBase + ["sounds_played"])
        publishNumber(
            counters.counters.playlistsStarted, components: countersBase + ["playlists_started"])
        publishNumber(
            counters.counters.playlistsStopped, components: countersBase + ["playlists_stopped"])
        publishNumber(
            counters.counters.playlistsEventsProcessed,
            components: countersBase + ["playlists_events_processed"])
        publishNumber(
            counters.counters.playlistStatusRequests,
            components: countersBase + ["playlist_status_requests"])
        publishNumber(
            counters.counters.restRequestsProcessed,
            components: countersBase + ["rest_requests_processed"])
        publishNumber(
            counters.counters.websocketConnectionsProcessed,
            components: countersBase + ["websocket_connections_processed"])
        publishNumber(
            counters.counters.websocketMessagesReceived,
            components: countersBase + ["websocket_messages_received"])
        publishNumber(
            counters.counters.websocketMessagesSent,
            components: countersBase + ["websocket_messages_sent"])
        publishNumber(
            counters.counters.websocketPingsSent,
            components: countersBase + ["websocket_pings_sent"]
        )
        publishNumber(
            counters.counters.websocketPongsReceived,
            components: countersBase + ["websocket_pongs_received"])

        for runtimeState in counters.runtimeStates {
            let resolved = resolveCreature(id: runtimeState.creatureId)
            publishIdentity(
                topicComponent: resolved.topicComponent, id: runtimeState.creatureId,
                name: resolved.resolvedName)
            if let runtime = runtimeState.runtime {
                if let idleEnabled = runtime.idleEnabled {
                    publishBool(
                        idleEnabled, components: [resolved.topicComponent, "idle", "enabled"])
                }
                if let activity = runtime.activity {
                    let activityBase = [resolved.topicComponent, "activity"]
                    publishValue(activity.state.rawValue, components: activityBase + ["state"])
                    if let animationId = activity.animationId {
                        publishValue(animationId, components: activityBase + ["animation_id"])
                        let animationName = animationNameResolver.resolve(
                            id: animationId, fetchIfMissing: fetchAnimationName)
                        publishValue(
                            animationName, components: activityBase + ["animation_name"])
                    }
                    if let sessionId = activity.sessionId {
                        publishValue(sessionId, components: activityBase + ["session_id"])
                    }
                    if let reason = activity.reason {
                        publishValue(reason.rawValue, components: activityBase + ["reason"])
                    }
                    if let startedAt = activity.startedAt {
                        publishDate(startedAt, components: activityBase + ["started_at"])
                    }
                    if let updatedAt = activity.updatedAt {
                        publishDate(updatedAt, components: activityBase + ["updated_at"])
                    }
                }
                if let counters = runtime.counters {
                    let runtimeCountersBase = [resolved.topicComponent, "counters"]
                    if let sessionsStarted = counters.sessionsStartedTotal {
                        publishNumber(
                            sessionsStarted, components: runtimeCountersBase + ["sessions_started"])
                    }
                    if let sessionsCancelled = counters.sessionsCancelledTotal {
                        publishNumber(
                            sessionsCancelled,
                            components: runtimeCountersBase + ["sessions_cancelled"])
                    }
                    if let idleStarted = counters.idleStartedTotal {
                        publishNumber(
                            idleStarted, components: runtimeCountersBase + ["idle_started_total"])
                    }
                    if let idleStopped = counters.idleStoppedTotal {
                        publishNumber(
                            idleStopped, components: runtimeCountersBase + ["idle_stopped_total"])
                    }
                    if let idleToggles = counters.idleTogglesTotal {
                        publishNumber(
                            idleToggles, components: runtimeCountersBase + ["idle_toggles_total"])
                    }
                    if let skips = counters.skipsMissingCreatureTotal {
                        publishNumber(
                            skips,
                            components: runtimeCountersBase + ["skips_missing_creature_total"])
                    }
                    if let bgmTakeovers = counters.bgmTakeoversTotal {
                        publishNumber(
                            bgmTakeovers, components: runtimeCountersBase + ["bgm_takeovers_total"])
                    }
                    if let audioResets = counters.audioResetsTotal {
                        publishNumber(
                            audioResets, components: runtimeCountersBase + ["audio_resets_total"])
                    }
                }
                if let bgmOwner = runtime.bgmOwner {
                    publishValue(bgmOwner, components: [resolved.topicComponent, "bgm_owner"])
                }
                if let lastError = runtime.lastError {
                    let errorBase = [resolved.topicComponent, "last_error"]
                    publishValue(lastError.message, components: errorBase + ["message"])
                    publishDate(lastError.timestamp, components: errorBase + ["timestamp"])
                }
            }
        }
    }

    func processWatchdogWarning(_ watchdogWarning: WatchdogWarning) {
        guard shouldPublish(.watchdogWarning) else { return }
        let base = ["watchdog", watchdogWarning.warningType]
        publishNumber(watchdogWarning.currentValue, components: base + ["current_value"])
        publishNumber(watchdogWarning.threshold, components: base + ["threshold"])
        publishDate(watchdogWarning.timestamp, components: base + ["timestamp"])
    }

    func processJobProgress(_ jobProgress: JobProgress) {
        guard shouldPublish(.jobProgress) else { return }
        let base = ["jobs", jobProgress.jobId]
        publishValue(jobProgress.jobType.rawValue, components: base + ["job_type"])
        publishValue(jobProgress.status.rawValue, components: base + ["status"])
        if let progress = jobProgress.progress {
            publishNumber(progress, components: base + ["progress"])
        }
        if let details = jobProgress.details {
            publishValue(details, components: base + ["details"])
        }
    }

    func processJobComplete(_ jobComplete: JobCompletion) {
        guard shouldPublish(.jobComplete) else { return }
        let base = ["jobs", jobComplete.jobId]
        publishValue(jobComplete.jobType.rawValue, components: base + ["job_type"])
        publishValue(jobComplete.status.rawValue, components: base + ["status"])
        if let result = jobComplete.result {
            publishValue(result, components: base + ["result"])
        }
        if let details = jobComplete.details {
            publishValue(details, components: base + ["details"])
        }
    }

    func processIdleStateChanged(_ idleState: IdleStateChanged) {
        guard shouldPublish(.idleStateChanged) else { return }
        let resolved = resolveCreature(id: idleState.creatureId)
        let base = [resolved.topicComponent, "idle"]
        publishIdentity(
            topicComponent: resolved.topicComponent, id: idleState.creatureId,
            name: resolved.resolvedName)
        publishBool(idleState.idleEnabled, components: base + ["enabled"])
        publishDate(idleState.timestamp, components: base + ["timestamp"])
    }

    func processCreatureActivity(_ activity: CreatureActivity) {
        guard shouldPublish(.creatureActivity) else { return }
        let resolved = resolveCreature(
            id: activity.creatureId, preferredName: activity.creatureName)
        let base = [resolved.topicComponent, "activity"]
        publishIdentity(
            topicComponent: resolved.topicComponent, id: activity.creatureId,
            name: resolved.resolvedName ?? activity.creatureName)
        publishValue(activity.state.rawValue, components: base + ["state"])
        if let animationId = activity.animationId {
            publishValue(animationId, components: base + ["animation_id"])
            let animationName = animationNameResolver.resolve(
                id: animationId, fetchIfMissing: fetchAnimationName)
            publishValue(animationName, components: base + ["animation_name"])
        }
        if let sessionId = activity.sessionId {
            publishValue(sessionId, components: base + ["session_id"])
        }
        if let reason = activity.reason {
            publishValue(reason.rawValue, components: base + ["reason"])
        }
        if let name = activity.creatureName {
            publishValue(name, components: base + ["name"])
        }
        publishDate(activity.timestamp, components: base + ["timestamp"])
    }
}
