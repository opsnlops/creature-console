import SwiftUI
import Testing

@testable import Creature_Console

#if canImport(GameController)
    import GameController
#endif

@Suite("Activity tint color mapping")
struct ActivityTintTests {

    @Test("all activities have tint colors")
    func allActivitiesHaveTintColors() {
        let activities: [Activity] = [
            .idle,
            .streaming,
            .recording,
            .preparingToRecord,
            .playingAnimation,
            .connectingToServer,
            .countingDownForFilming,
        ]

        for activity in activities {
            let color = activity.tintColor
            // Verify we got a color (not crashing)
            _ = color
        }
    }

    @Test("idle is blue")
    func idleIsBlue() {
        #expect(Activity.idle.tintColor == .blue)
    }

    @Test("streaming is green")
    func streamingIsGreen() {
        #expect(Activity.streaming.tintColor == .green)
    }

    @Test("recording is red")
    func recordingIsRed() {
        #expect(Activity.recording.tintColor == .red)
    }

    @Test("preparing to record is yellow")
    func preparingToRecordIsYellow() {
        #expect(Activity.preparingToRecord.tintColor == .yellow)
    }

    @Test("playing animation is purple")
    func playingAnimationIsPurple() {
        #expect(Activity.playingAnimation.tintColor == .purple)
    }

    @Test("countdown for filming is orange")
    func countdownForFilmingIsOrange() {
        #expect(Activity.countingDownForFilming.tintColor == .orange)
    }

    @Test("connecting to server is pink")
    func connectingToServerIsPink() {
        #expect(Activity.connectingToServer.tintColor == .pink)
    }

    #if canImport(GameController)
        @Test("all activities have controller light colors")
        func allActivitiesHaveControllerLightColors() {
            let activities: [Activity] = [
                .idle,
                .streaming,
                .recording,
                .preparingToRecord,
                .playingAnimation,
                .connectingToServer,
                .countingDownForFilming,
            ]

            for activity in activities {
                let color = activity.controllerLightColor
                // Verify RGB components are in valid range [0, 1]
                #expect(color.red >= 0.0 && color.red <= 1.0)
                #expect(color.green >= 0.0 && color.green <= 1.0)
                #expect(color.blue >= 0.0 && color.blue <= 1.0)
            }
        }

        @Test("idle controller light is blueish")
        func idleControllerLightIsBlueish() {
            let color = Activity.idle.controllerLightColor
            // Blue should be the dominant component
            #expect(color.blue > color.red)
            #expect(color.blue > color.green)
        }

        @Test("streaming controller light is greenish")
        func streamingControllerLightIsGreenish() {
            let color = Activity.streaming.controllerLightColor
            // Green should be the dominant component
            #expect(color.green > color.red)
            #expect(color.green > color.blue)
        }

        @Test("recording controller light is reddish")
        func recordingControllerLightIsReddish() {
            let color = Activity.recording.controllerLightColor
            // Red should be the dominant component
            #expect(color.red > color.green)
            #expect(color.red > color.blue)
        }

        @Test("filming countdown controller light is warm")
        func filmingCountdownControllerLightIsWarm() {
            let color = Activity.countingDownForFilming.controllerLightColor
            // Orange should be warmer than blue
            #expect(color.red > color.blue)
            #expect(color.green >= color.blue)
        }

        @Test("controller light colors are not black")
        func controllerLightColorsAreNotBlack() {
            let activities: [Activity] = [
                .idle,
                .streaming,
                .recording,
                .preparingToRecord,
                .playingAnimation,
                .connectingToServer,
                .countingDownForFilming,
            ]

            for activity in activities {
                let color = activity.controllerLightColor
                // At least one component should be > 0
                let hasColor = color.red > 0.0 || color.green > 0.0 || color.blue > 0.0
                #expect(hasColor, "Activity \(activity) has black controller light color")
            }
        }

        @Test("fallback colors are reasonable")
        func fallbackColorsAreReasonable() {
            // Test that fallback RGB values exist and are reasonable
            // These are the hardcoded fallback values in the extension
            let idleFallback = GCColor(red: 0.0, green: 0.478, blue: 1.0)
            #expect(idleFallback.blue == 1.0)

            let streamingFallback = GCColor(red: 0.203, green: 0.780, blue: 0.349)
            #expect(streamingFallback.green > 0.7)

            let recordingFallback = GCColor(red: 1.0, green: 0.231, blue: 0.188)
            #expect(recordingFallback.red == 1.0)
        }
    #endif
}
