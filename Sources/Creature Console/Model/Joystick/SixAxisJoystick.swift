import Combine
import Common
import CoreHaptics
import Foundation
import GameController
import OSLog
import SwiftUI

class Axis: ObservableObject, CustomStringConvertible {
    var axisType: AxisType = .gamepad
    @Published var name: String = ""
    @Published var value: UInt8 = 127

    var rawValue: Float = 0 {
        didSet {

            var mappedvalue = Float(0.0)

            switch axisType {
            case (.gamepad):
                // The raw value is a value of -1.0 to 1.0, where the center is 0. Let's map this to a value that we normally use on our creature joysticks
                mappedvalue = Float(UInt8.max) * Float((rawValue + 1.0) / 2)

            default:
                mappedvalue = Float(UInt8.max) * Float(rawValue)
            }

            value = UInt8(round(mappedvalue))
        }
    }

    var description: String {
        return String(value)
    }

    enum AxisType: CustomStringConvertible {
        case gamepad
        case trigger

        var description: String {
            switch self {
            case .gamepad:
                return "Gamepad"
            case .trigger:
                return "Trigger"
            }
        }
    }
}


class SixAxisJoystick: ObservableObject, Joystick {

    @Published var axises: [Axis]
    @Published var aButtonPressed = false
    @Published var bButtonPressed = false
    @Published var xButtonPressed = false
    @Published var yButtonPressed = false

    // Note: AppState access removed for Swift 6 actor compatibility
    var controller: GCController?
    let objectWillChange = ObservableObjectPublisher()
    let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "SixAxisJoystick")

    @AppStorage("logJoystickPollEvents") var logJoystickPollEvents: Bool = false

    private var cancellables: Set<AnyCancellable> = []

    // Retain a controller haptics engine for countdown pulses so it isn't deallocated between calls
    private var countdownHapticsEngine: CHHapticEngine?

    #if os(iOS)
        var virtualJoysick = VirtualJoystick()
        var virtualJoystickConnected = false
    #endif

    var manufacturer: String {
        controller?.vendorName ?? "🎮"
    }

    var versionNumber: Int {
        return -1
    }

    var serialNumber: String {
        return "Unknown S/N"
    }

    init() {
        self.axises = []

        for _ in 0...5 {
            self.axises.append(Axis())
        }

        // Axies 4 and 5 are triggers
        self.axises[4].axisType = .trigger
        self.axises[5].axisType = .trigger
        self.axises[4].value = 0
        self.axises[5].value = 0

        // Pay attention to the joystick, even when in the background
        GCController.shouldMonitorBackgroundEvents = true

        // Note: Joystick light updates now handled by JoystickManager for Swift 6 compatibility

    }

    deinit {
        for cancellable in cancellables {
            cancellable.cancel()
        }
    }

    var changesPublisher: AnyPublisher<Void, Never> {
        objectWillChange.eraseToAnyPublisher()
    }

    func getValues() -> [UInt8] {
        return axises.map { $0.value }
    }

    func isConnected() -> Bool {
        return controller != nil
    }


    func getAButtonSymbol() -> String {
        return controller?.extendedGamepad?.buttonA.sfSymbolsName ?? "a.circle"
    }
    func getBButtonSymbol() -> String {
        return controller?.extendedGamepad?.buttonB.sfSymbolsName ?? "b.circle"
    }
    func getXButtonSymbol() -> String {
        return controller?.extendedGamepad?.buttonX.sfSymbolsName ?? "x.circle"
    }
    func getYButtonSymbol() -> String {
        return controller?.extendedGamepad?.buttonY.sfSymbolsName ?? "y.circle"
    }


    func updateJoystickLight(activity: Activity) {
        // Update the light when this changes
        guard let controller = self.controller else {
            logger.debug("No controller available for joystick light update")
            return
        }
        let color = activity.controllerLightColor
        logger.info(
            "SixAxisJoystick: Setting joystick light to RGB(\(color.red),\(color.green),\(color.blue)) for activity: \(activity.description)"
        )
        controller.light?.color = color
        logger.info("SixAxisJoystick: Light color set successfully")
    }

    func showVirtualJoystickIfNeeded() {

        #if os(iOS)
            if GCController.controllers().isEmpty {
                logger.info("creating virtual joystick")
                virtualJoysick.create()
                virtualJoysick.connect()
                virtualJoystickConnected = true
            }
        #endif

    }

    func removeVirtualJoystickIfNeeded() {
        #if os(iOS)
            if virtualJoystickConnected {
                virtualJoysick.disconnect()
                virtualJoystickConnected = false
                logger.info("disconnecting virtual joystick")
            }
        #endif
    }


    func poll() {

        if let joystick = controller?.extendedGamepad {

            var didChange = false

            if axises[0].rawValue != joystick.leftThumbstick.xAxis.value {
                axises[0].rawValue = joystick.leftThumbstick.xAxis.value
                didChange = true
            }

            if axises[1].rawValue != joystick.leftThumbstick.yAxis.value {
                axises[1].rawValue = joystick.leftThumbstick.yAxis.value
                didChange = true
            }

            if axises[2].rawValue != joystick.rightThumbstick.xAxis.value {
                axises[2].rawValue = joystick.rightThumbstick.xAxis.value
                didChange = true
            }

            if axises[3].rawValue != joystick.rightThumbstick.yAxis.value {
                axises[3].rawValue = joystick.rightThumbstick.yAxis.value
                didChange = true
            }

            if axises[4].rawValue != joystick.leftTrigger.value {
                axises[4].rawValue = joystick.leftTrigger.value
                didChange = true
            }

            if axises[5].rawValue != joystick.rightTrigger.value {
                axises[5].rawValue = joystick.rightTrigger.value
                didChange = true
            }

            if joystick.buttonA.isPressed != self.aButtonPressed {
                self.aButtonPressed = joystick.buttonA.isPressed
                didChange = true
            }

            if joystick.buttonB.isPressed != self.bButtonPressed {
                self.bButtonPressed = joystick.buttonB.isPressed
                didChange = true
            }

            if joystick.buttonX.isPressed != self.xButtonPressed {
                self.xButtonPressed = joystick.buttonX.isPressed
                didChange = true
            }

            if joystick.buttonY.isPressed != self.yButtonPressed {
                self.yButtonPressed = joystick.buttonY.isPressed
                didChange = true
            }

            // This is noisy! Make it optional
            if logJoystickPollEvents {
                logger.debug("joystick polling done")
            }

            // If there's a change to be propogated out, send immediately since we're now inside an actor
            if didChange {
                self.objectWillChange.send()
            }
        } else {
            logger.info("skipping polling because not extended gamepad")
        }

    }

}

// SixAxisJoystick is used across actor boundaries only to schedule @MainActor haptic work.
// Marking it @unchecked Sendable is safe in this context because all mutable state that
// interacts with system frameworks (GameController/CoreHaptics) is accessed on the main actor.
extension SixAxisJoystick: @unchecked Sendable {}

@MainActor
extension SixAxisJoystick {
    /// Task used to coordinate and cancel any in-flight countdown sequence.
    private static var recordingCountdownTask: Task<Void, Never>? = nil

    /// Plays a short countdown rumble sequence at 2.0s, 2.5s, 3.0s and a heavy pulse at 3.5s.
    /// Call this at the same moment you start the countdown audio.
    func playRecordingCountdownHaptics() {
        // Cancel any existing sequence first
        SixAxisJoystick.recordingCountdownTask?.cancel()
        SixAxisJoystick.recordingCountdownTask = Task { @MainActor in
            await self.playCountdown(times: [
                (seconds: 2.0, intensity: 0.45, sharpness: 0.4, duration: 0.06),
                (seconds: 2.5, intensity: 0.65, sharpness: 0.4, duration: 0.06),
                (seconds: 3.0, intensity: 0.85, sharpness: 0.4, duration: 0.06),
                (seconds: 3.5, intensity: 1.0, sharpness: 0.9, duration: 0.20),
            ])
        }
    }

    /// Cancel any pending countdown pulses (e.g., user backs out).
    func cancelRecordingCountdownHaptics() {
        SixAxisJoystick.recordingCountdownTask?.cancel()
        SixAxisJoystick.recordingCountdownTask = nil
        Task { @MainActor in
            do {
                try await countdownHapticsEngine?.stop()
            } catch {
                logger.debug(
                    "Failed to stop haptics engine on cancel: \(String(describing: error))")
            }
        }
        countdownHapticsEngine = nil
    }

    /// Convenience methods to safely trigger/cancel the countdown from any actor context.
    nonisolated func playRecordingCountdownHapticsFromAnyActor() async {
        await MainActor.run { self.playRecordingCountdownHaptics() }
    }

    nonisolated func cancelRecordingCountdownHapticsFromAnyActor() async {
        await MainActor.run { self.cancelRecordingCountdownHaptics() }
    }

    // MARK: - Private helpers

    /// Play a single transient pulse using an AHAP dictionary via Core Haptics.
    private func playPulse(intensity: Float, sharpness: Float, duration: Double) {
        guard let controller = self.controller, let haptics = controller.haptics else {
            logger.debug("Haptics unavailable on controller; skipping pulse")
            return
        }

        // Lazily create and start a retained engine
        if countdownHapticsEngine == nil {
            // Prefer the right handle where the face buttons are located on DualSense
            countdownHapticsEngine =
                haptics.createEngine(withLocality: .all)
                ?? haptics.createEngine(withLocality: .default)
            do {
                try countdownHapticsEngine?.start()
            } catch {
                logger.error(
                    "Failed to start controller haptics engine: \(String(describing: error))")
                countdownHapticsEngine = nil
                return
            }
        }

        guard let engine = countdownHapticsEngine else { return }

        do {
            let pattern: CHHapticPattern
            if duration > 0 {
                // Use a continuous event for a stronger, longer pulse
                let event = CHHapticEvent(
                    eventType: .hapticContinuous,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
                    ],
                    relativeTime: 0,
                    duration: duration)
                pattern = try CHHapticPattern(events: [event], parameters: [])
            } else {
                // Short transient tap
                let event = CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
                    ],
                    relativeTime: 0)
                pattern = try CHHapticPattern(events: [event], parameters: [])
            }

            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
        } catch {
            logger.error("Failed to play controller haptic: \(String(describing: error))")
        }
    }

    /// Schedule pulses at absolute offsets from now using ContinuousClock for precise timing.
    private func playCountdown(
        times: [(seconds: Double, intensity: Float, sharpness: Float, duration: Double)]
    ) async {
        let clock = ContinuousClock()
        let start = clock.now
        for (sec, intensity, sharpness, duration) in times {
            let deadline = start.advanced(by: .seconds(sec))
            do {
                try await clock.sleep(until: deadline)
            } catch {
                // Cancelled or interrupted
                return
            }
            // We are on @MainActor; safe to touch controller.
            playPulse(intensity: intensity, sharpness: sharpness, duration: duration)
        }
        // Ensure the final pulse (especially continuous) has time to complete before stopping the engine
        if let last = times.last, last.duration > 0 {
            try? await Task.sleep(for: .seconds(last.duration))
        }
        // After finishing the sequence, stop and release the engine
        do {
            try await countdownHapticsEngine?.stop()
        } catch {
            logger.debug(
                "Failed to stop haptics engine after sequence: \(String(describing: error))")
        }
        countdownHapticsEngine = nil
    }
}

extension SixAxisJoystick {
    static func mock() -> SixAxisJoystick {
        let joystick = SixAxisJoystick()

        for axis in joystick.axises {
            axis.value = UInt8(arc4random_uniform(UInt32(UInt8.max)))
        }

        return joystick
    }
}
