import Foundation
import SwiftData

/// Serializes `ModelContainer` creation across the whole test process.
///
/// Swift Testing runs suites in parallel, and concurrent container creation races inside
/// CoreData's model archiving (`saveCachedModel` / `NSKeyedArchiver` over shared
/// `NSManagedObjectModel` state), killing the test host with pointer-authentication
/// failures (issue #38). One lock around creation removes the only cross-suite shared
/// state; the containers themselves stay independent and in-memory.
private let testContainerCreationLock = NSLock()

func makeTestModelContainer(schema: Schema, configuration: ModelConfiguration) throws
    -> ModelContainer
{
    testContainerCreationLock.lock()
    defer { testContainerCreationLock.unlock() }
    return try ModelContainer(for: schema, configurations: [configuration])
}
