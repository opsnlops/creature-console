import Common
import Foundation
import OSLog
import SwiftUI

/// The one `@MainActor` observable projection of the app's live actor state.
///
/// Before this existed, every chrome view ran its own `for await` mirror loops over
/// `AppState` / `StatusLightsManager` / `WebSocketStateManager` / `JoystickManager`
/// streams — the same triad was copy-pasted verbatim across TopContentView,
/// BottomStatusToolbarContent, and BottomToolBarView, each mirroring snapshots into local
/// `@State`. This store subscribes once and republishes the latest snapshots as plain
/// observable properties; views just read them (injected via `.environment(...)`).
///
/// Deliberately **not** bridged here:
/// - RecordTrack's joystick consumption — B-button *edge* detection needs the unbounded
///   event stream, not a coalesced snapshot (see the stream-buffering notes in
///   JoystickManager).
/// - Per-job event streams (`.watchJob`) — event semantics, not state snapshots.
@MainActor
@Observable
final class ConsoleStore {
    static let shared = ConsoleStore()

    private(set) var appState = AppStateData(
        currentActivity: .idle,
        currentAnimation: nil,
        selectedTrack: nil,
        showSystemAlert: false,
        systemAlertMessage: ""
    )
    private(set) var statusLights = StatusLightsState(
        running: false, dmx: false, streaming: false, animationPlaying: false)
    private(set) var websocketState: WebSocketConnectionState = .disconnected
    private(set) var joystick = JoystickManagerState(
        aButtonPressed: false, bButtonPressed: false, xButtonPressed: false,
        yButtonPressed: false, selectedJoystick: .sixAxis)

    /// Shorthand for the most commonly read field.
    var currentActivity: Activity { appState.currentActivity }

    private init() {
        // One eternal subscription per source. The tasks inherit MainActor isolation, and
        // the snapshot streams use bufferingNewest(1), so a busy main thread skips straight
        // to the freshest value instead of draining a backlog.
        Task {
            for await state in await AppState.shared.stateUpdates {
                self.appState = state
            }
        }
        Task {
            for await state in await StatusLightsManager.shared.stateUpdates {
                self.statusLights = state
            }
        }
        Task {
            self.websocketState = await WebSocketStateManager.shared.getCurrentState
            for await state in await WebSocketStateManager.shared.stateUpdates {
                self.websocketState = state
            }
        }
        Task {
            for await state in await JoystickManager.shared.stateUpdates {
                self.joystick = state
            }
        }
    }
}
