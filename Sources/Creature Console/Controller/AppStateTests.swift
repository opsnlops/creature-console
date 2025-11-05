import Common
import Foundation
import Testing

@testable import Creature_Console

@Suite("AppState singleton and state management")
struct AppStateTests {

    @Test("singleton returns same instance")
    func singletonReturnsSameInstance() async {
        let instance1 = AppState.shared
        let instance2 = AppState.shared

        #expect(instance1 === instance2)
    }

    @Test("getCurrentState returns current snapshot")
    func getCurrentStateReturnsSnapshot() async {
        let appState = AppState.shared
        await appState.setCurrentActivity(.idle)

        let state = await appState.getCurrentState()
        #expect(state.currentActivity == .idle)
    }

    @Test("setCurrentActivity updates activity")
    func setCurrentActivityUpdates() async {
        let appState = AppState.shared

        await appState.setCurrentActivity(.streaming)
        let activity = await appState.getCurrentActivity

        #expect(activity == .streaming)

        await appState.setCurrentActivity(.idle)
    }

    @Test("setCurrentAnimation updates animation")
    func setCurrentAnimationUpdates() async {
        let appState = AppState.shared
        let testAnimation = Animation.mock()

        await appState.setCurrentAnimation(testAnimation)
        let animation = await appState.getCurrentAnimation

        #expect(animation?.id == testAnimation.id)

        await appState.setCurrentAnimation(nil)
    }

    @Test("setSelectedTrack updates track")
    func setSelectedTrackUpdates() async {
        let appState = AppState.shared
        let testTrack = "creature_123"

        await appState.setSelectedTrack(testTrack)
        let track = await appState.getSelectedTrack

        #expect(track == testTrack)

        await appState.setSelectedTrack(nil)
    }

    @Test("setSystemAlert updates alert state")
    func setSystemAlertUpdates() async {
        let appState = AppState.shared

        await appState.setSystemAlert(show: true, message: "Test alert")
        let showAlert = await appState.getShowSystemAlert
        let message = await appState.getSystemAlertMessage

        #expect(showAlert == true)
        #expect(message == "Test alert")

        await appState.setSystemAlert(show: false, message: "")
    }

    @Test("Activity description strings are correct")
    func activityDescriptionsAreCorrect() {
        #expect(Activity.idle.description == "Idle")
        #expect(Activity.streaming.description == "Streaming")
        #expect(Activity.recording.description == "Recording")
        #expect(Activity.preparingToRecord.description == "Preparing to Record")
        #expect(Activity.playingAnimation.description == "Playing Animation")
        #expect(Activity.connectingToServer.description == "Connecting to Server")
        #expect(Activity.countingDownForFilming.description == "Countdown for Filming")
    }

    @Test("AppStateData is Sendable")
    func appStateDataIsSendable() {
        // This is a compile-time check - if AppStateData isn't Sendable, this won't compile
        let data = AppStateData(
            currentActivity: .idle,
            currentAnimation: nil,
            selectedTrack: nil,
            showSystemAlert: false,
            systemAlertMessage: ""
        )

        Task {
            // Should be able to send across actor boundaries
            _ = data
        }
    }

    @Test("Activity is Sendable")
    func activityIsSendable() {
        // Compile-time check for Sendable conformance
        let activity = Activity.streaming

        Task {
            _ = activity
        }
    }

    @Test("getCurrentActivity getter returns current activity")
    func getCurrentActivityReturnsCorrect() async {
        let appState = AppState.shared

        await appState.setCurrentActivity(.streaming)
        let activity = await appState.getCurrentActivity

        #expect(activity == .streaming)

        await appState.setCurrentActivity(.idle)
    }

    @Test("state snapshot is independent")
    func stateSnapshotIsIndependent() async {
        let appState = AppState.shared

        await appState.setCurrentActivity(.streaming)
        let snapshot1 = await appState.getCurrentState()

        await appState.setCurrentActivity(.recording)
        let snapshot2 = await appState.getCurrentState()

        // Snapshots should be different
        #expect(snapshot1.currentActivity == .streaming)
        #expect(snapshot2.currentActivity == .recording)

        await appState.setCurrentActivity(.idle)
    }
}
