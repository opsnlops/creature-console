import Foundation
import Logging

/// Where the mind resumes in the world's ordered history.
protocol WorldCursorStore: Sendable {
    /// The sequence to resume after, or `nil` when this world has never been observed.
    func current() async -> Int64?
    /// Records that everything up to and including `sequence` has been decided.
    func advance(to sequence: Int64) async throws
}

/// The mind's durable place in the world's ordered history.
///
/// The cursor is the last world sequence this agent has fully dealt with — answered, or
/// deliberately stayed silent about. It is advanced only after that decision is durable, so a
/// restart replays anything undecided and never skips a turn. The cursor is bound to the World
/// URL it was recorded against; pointing the agent at a different world starts it fresh.
actor WorldAgentCursor: WorldCursorStore {
    struct Position: Codable, Equatable, Sendable {
        let worldURL: String
        let worldSequence: Int64

        private enum CodingKeys: String, CodingKey {
            case worldURL = "world_url"
            case worldSequence = "world_sequence"
        }
    }

    private let fileURL: URL
    private let worldURL: String
    private let logger: Logger
    private var position: Position?

    init(stateDirectory: URL, worldURL: URL, logger: Logger) {
        self.fileURL = stateDirectory.appendingPathComponent("world-cursor.json")
        self.worldURL = worldURL.absoluteString
        self.logger = logger
    }

    /// The sequence to resume after, or `nil` when this world has never been observed.
    func current() -> Int64? {
        if let position {
            return position.worldSequence
        }
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        do {
            let stored = try JSONDecoder().decode(Position.self, from: data)
            guard stored.worldURL == worldURL else {
                logger.warning(
                    "Ignoring world cursor recorded against a different world",
                    metadata: [
                        "cursor.world_url": "\(stored.worldURL)",
                        "world.url": "\(worldURL)",
                    ]
                )
                return nil
            }
            position = stored
            return stored.worldSequence
        } catch {
            logger.warning(
                "Ignoring unreadable world cursor",
                metadata: ["cursor.path": "\(fileURL.path)", "error": "\(error)"]
            )
            return nil
        }
    }

    /// Records that everything up to and including `sequence` has been decided.
    func advance(to sequence: Int64) throws {
        if let position, position.worldSequence >= sequence {
            return
        }
        let updated = Position(worldURL: worldURL, worldSequence: sequence)
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        // `.atomic` writes a temporary file and renames it into place on macOS and Linux;
        // FileManager.replaceItemAt is not portable when the destination does not exist yet.
        try JSONEncoder().encode(updated).write(to: fileURL, options: .atomic)
        position = updated
    }
}
