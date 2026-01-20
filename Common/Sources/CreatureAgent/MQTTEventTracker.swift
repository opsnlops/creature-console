import Foundation
import Logging

actor MQTTEventTracker {
    private var lastSeenByTopic: [String: TimeInterval] = [:]
    private var lastSeenByArea: [String: TimeInterval] = [:]
    private var hasSeenLiveByTopic: [String: Bool] = [:]
    private let logger: Logger

    init(logger: Logger) {
        self.logger = logger
    }

    func shouldProcess(topic: String, timestamp: TimeInterval?) -> Bool {
        guard let timestamp else {
            logger.debug("MQTT payload missing timestamp for \(topic)")
            return false
        }

        if let lastTimestamp = lastSeenByTopic[topic] {
            if timestamp <= lastTimestamp {
                return false
            }
        }

        lastSeenByTopic[topic] = timestamp
        hasSeenLiveByTopic[topic] = true
        return true
    }

    func cooldownWindow(for area: String, cooldownSeconds: TimeInterval) -> TimeInterval? {
        guard cooldownSeconds > 0 else {
            return nil
        }
        guard let lastTimestamp = lastSeenByArea[area] else {
            return nil
        }
        let elapsed = Date().timeIntervalSince1970 - lastTimestamp
        if elapsed < cooldownSeconds {
            return cooldownSeconds - elapsed
        }
        return nil
    }

    func markAreaProcessed(_ area: String) {
        lastSeenByArea[area] = Date().timeIntervalSince1970
    }

    func initialTimestamp(for topic: String) -> TimeInterval? {
        lastSeenByTopic[topic]
    }

    func updateInitialTimestamp(for topic: String, timestamp: TimeInterval?) {
        guard let timestamp else { return }
        if hasSeenLiveByTopic[topic] == true {
            return
        }
        if let lastTimestamp = lastSeenByTopic[topic], timestamp <= lastTimestamp {
            return
        }
        lastSeenByTopic[topic] = timestamp
    }

    nonisolated static func timestamp(from payload: String) -> TimeInterval? {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let value = Double(trimmed) else {
            return nil
        }
        if value >= 1_000_000_000_000 {
            return value / 1000
        }
        return value
    }
}
