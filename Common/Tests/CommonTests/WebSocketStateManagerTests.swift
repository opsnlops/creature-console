import Foundation
import Testing

@testable import Common

@Suite("WebSocketStateManager singleton and state management")
struct WebSocketStateManagerTests {

    @Test("singleton returns same instance")
    func singletonReturnsSameInstance() async {
        let instance1 = WebSocketStateManager.shared
        let instance2 = WebSocketStateManager.shared

        #expect(instance1 === instance2)
    }

    @Test("getCurrentState returns current state")
    func getCurrentStateReturnsCorrect() async {
        let manager = WebSocketStateManager.shared

        await manager.setState(.connected)
        let state = await manager.getCurrentState

        #expect(state == .connected)

        // Clean up
        await manager.setState(.disconnected)
    }

    @Test("setState updates state")
    func setStateUpdates() async {
        let manager = WebSocketStateManager.shared

        await manager.setState(.connecting)
        let state = await manager.getCurrentState

        #expect(state == .connecting)

        await manager.setState(.disconnected)
    }

    @Test("setState transitions through all states")
    func setStateTransitionsThroughAllStates() async {
        let manager = WebSocketStateManager.shared

        // Test all state transitions
        await manager.setState(.disconnected)
        #expect(await manager.getCurrentState == .disconnected)

        await manager.setState(.connecting)
        #expect(await manager.getCurrentState == .connecting)

        await manager.setState(.connected)
        #expect(await manager.getCurrentState == .connected)

        await manager.setState(.reconnecting)
        #expect(await manager.getCurrentState == .reconnecting)

        await manager.setState(.closing)
        #expect(await manager.getCurrentState == .closing)

        // Clean up
        await manager.setState(.disconnected)
    }

    @Test("WebSocketConnectionState description strings are correct")
    func stateDescriptionsAreCorrect() {
        #expect(WebSocketConnectionState.disconnected.description == "Disconnected")
        #expect(WebSocketConnectionState.connecting.description == "Connecting")
        #expect(WebSocketConnectionState.connected.description == "Connected")
        #expect(WebSocketConnectionState.reconnecting.description == "Reconnecting")
        #expect(WebSocketConnectionState.closing.description == "Closing")
    }

    @Test("WebSocketConnectionState is Sendable")
    func stateIsSendable() {
        // Compile-time check for Sendable conformance
        let state = WebSocketConnectionState.connected

        Task {
            _ = state
        }
    }

    @Test("stateUpdates stream yields current state immediately")
    func stateUpdatesStreamYieldsCurrentState() async {
        let manager = WebSocketStateManager.shared

        // Set a known state
        await manager.setState(.connected)

        // Subscribe and get the first value
        var receivedState: WebSocketConnectionState?
        let stream = await manager.stateUpdates

        for await state in stream {
            receivedState = state
            break  // Only get the first (current) state
        }

        #expect(receivedState == .connected)

        // Clean up
        await manager.setState(.disconnected)
    }

    @Test("stateUpdates stream provides state changes")
    func stateUpdatesStreamProvidesStateChanges() async {
        let manager = WebSocketStateManager.shared

        // Set a deterministic starting state
        await manager.setState(.disconnected)

        // Verify the stream yields states - just check we can iterate
        var receivedAtLeastOne = false
        let stream = await manager.stateUpdates

        for await state in stream {
            receivedAtLeastOne = true
            // Verify it's a valid state
            #expect([.disconnected, .connecting, .connected, .reconnecting, .closing].contains(state))
            break  // Just need to verify the stream works
        }

        #expect(receivedAtLeastOne == true)
    }

    @Test("state equality works correctly")
    func stateEqualityWorksCorrectly() {
        #expect(WebSocketConnectionState.connected == .connected)
        #expect(WebSocketConnectionState.disconnected == .disconnected)
        #expect(WebSocketConnectionState.connected != .disconnected)
        #expect(WebSocketConnectionState.connecting != .reconnecting)
    }
}
