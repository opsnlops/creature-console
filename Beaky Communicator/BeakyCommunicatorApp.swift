import CreatureAppSupport
import Foundation
import SwiftData
import SwiftUI

@main
struct BeakyCommunicatorApp: App {
    private let modelContainer: ModelContainer
    private let conversationService: any CommunicatorConversationService

    init() {
        do {
            let schema = Schema([ConversationItemModel.self])
            let configuration: ModelConfiguration
            if Self.isRunningTests {
                configuration = ModelConfiguration(isStoredInMemoryOnly: true)
            } else {
                let applicationSupport = try FileManager.default.url(
                    for: .applicationSupportDirectory,
                    in: .userDomainMask,
                    appropriateFor: nil,
                    create: true
                )
                configuration = ModelConfiguration(
                    url: applicationSupport.appendingPathComponent("BeakyCommunicatorStore")
                )
            }

            let container = try ModelContainer(for: schema, configurations: configuration)
            modelContainer = container
            conversationService = SwiftDataConversationService(modelContainer: container)
        } catch {
            fatalError("Failed to create Beaky Communicator SwiftData store: \(error)")
        }
    }

    var body: some Scene {
        #if os(macOS)
            WindowGroup {
                ConversationRootView(service: conversationService)
            }
            .defaultSize(width: 760, height: 720)
            .modelContainer(modelContainer)

            Settings {
                CommunicatorSettingsView()
                    .frame(width: 540, height: 500)
            }
            .modelContainer(modelContainer)
        #else
            WindowGroup {
                ConversationRootView(service: conversationService)
            }
            .modelContainer(modelContainer)
        #endif
    }

    private static var isRunningTests: Bool {
        NSClassFromString("XCTestCase") != nil
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.environment["XCTestSessionIdentifier"] != nil
    }
}
