import Foundation

/// True when this process is hosting a test run rather than serving a human.
///
/// The full app must not boot under the test runner: the WebSocket pipeline streams server
/// logs into the real SwiftData store while test suites create model containers in parallel,
/// which races CoreData's model archiving and segfaults the test host (issue #38).
enum TestRun {
    static let isActive: Bool =
        NSClassFromString("XCTestCase") != nil
        || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        || ProcessInfo.processInfo.environment["XCTestSessionIdentifier"] != nil
}
