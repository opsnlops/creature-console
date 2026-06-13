import Foundation
import MongoKitten

/// An error from the database migration/back-fill helpers, carrying a user-facing message.
/// Thrown out of a command's `run()`, ArgumentParser prints it as `Error: <message>`.
public struct MigrationError: Error, LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// Connects to a creature MongoDB server, printing a progress line and turning any
/// connection failure into a clean `MigrationError` that names the role and address.
///
/// `role` is a human label such as "mainline" or "travel" used in the messages.
public func connectCreatureDatabase(
    server: String, port: Int, database: String, role: String
) async throws -> MongoDatabase {
    let uri = try MongoServerAddress.connectionURI(for: server, database: database, port: port)
    print("Connecting to \(role) server at \(server)...")
    do {
        return try await MongoDatabase.connect(to: uri)
    } catch {
        throw MigrationError("Unable to connect to the \(role) server (\(server)): \(error)")
    }
}
