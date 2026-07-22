import Common
import Foundation
import OSLog

/// The 50 Hz heartbeat of the console.
///
/// A structured `ContinuousClock` loop owned by this actor: each tick polls the joystick and
/// then runs the creature manager's tick **in order** (streaming frames always see the freshest
/// joystick values), and back-pressure is real — if a tick overruns its frame budget the loop
/// simply starts the next one late instead of piling up unstructured Tasks.
actor EventLoop {

    // Make a singleton out of this
    static let shared = EventLoop()

    private var loopTask: Task<Void, Never>?
    private(set) var number_of_frames: Int64 = 0

    /**
     Keep track of how much spare time we have in each frame. I have nothing but very fast Macs, so this should rarely be
     an issue, but if it is, I'd like for it to be shown to the status bar
     */

    var frameSpareTime: Double = 0
    var localFrameSpareTime: Double = 0  // Updated every loop

    private var millisecondPerFrame: Int
    private var logSpareTimeFrameInterval: Int
    private var logSpareTime: Bool
    private var updateSpareTimeStatusInterval: Int

    private let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "EventLoop")
    private let numberFormatter = NumberFormatter()


    /// Start up all of the things
    init() {

        self.frameSpareTime = 100.0

        // Read configuration once at startup
        let defaults = UserDefaults.standard
        self.millisecondPerFrame =
            (defaults.object(forKey: "eventLoopMillisecondsPerFrame") as? Int) ?? 20
        self.logSpareTimeFrameInterval =
            (defaults.object(forKey: "logSpareTimeFrameInterval") as? Int) ?? 1000
        self.logSpareTime = (defaults.object(forKey: "logSpareTime") as? Bool) ?? false
        self.updateSpareTimeStatusInterval =
            (defaults.object(forKey: "updateSpareTimeStatusInterval") as? Int) ?? 20

        // Configure the number formatter
        numberFormatter.numberStyle = .decimal
        numberFormatter.maximumFractionDigits = 2
        numberFormatter.minimumFractionDigits = 2

        Task {
            await startLoop()
        }

        logger.info("event loop started")
    }

    deinit {
        loopTask?.cancel()
        logger.info("event loop stopped")
    }


    /// One frame of the event loop
    private func tick() async {

        let clock = ContinuousClock()
        let startTime = clock.now

        // Update our metrics
        number_of_frames += 1

        // Poll the joystick first, then let the creature manager consume the fresh values
        await JoystickManager.shared.poll()
        await CreatureManager.shared.onEventLoopTick()

        // Figure out our spare time this cycle
        let elapsed = clock.now - startTime
        let elapsedTimeInMilliseconds =
            Double(elapsed.components.seconds) * 1_000.0
            + Double(elapsed.components.attoseconds) / 1e15
        localFrameSpareTime =
            (1 - (elapsedTimeInMilliseconds / Double(millisecondPerFrame))) * 100.0

        // If it's time to print out a logging message with our info, do it now
        if self.logSpareTime && number_of_frames % Int64(logSpareTimeFrameInterval) == 1 {

            let elapsedTimeString =
                numberFormatter.string(from: NSNumber(value: elapsedTimeInMilliseconds)) ?? "0.00"
            let idleTimeString =
                numberFormatter.string(from: NSNumber(value: localFrameSpareTime)) ?? "0.00"

            logger.trace("Frame time: \(elapsedTimeString)ms (\(idleTimeString)% Idle)")
        }

        // Send an update to things watching us every `updateSpareTimeStatusInterval` frames
        if number_of_frames % Int64(updateSpareTimeStatusInterval) == 1 {
            self.frameSpareTime = self.localFrameSpareTime
        }

    }


    private func startLoop() {
        logger.info("Starting event loop at \(self.millisecondPerFrame)ms per frame")

        let period = Duration.milliseconds(millisecondPerFrame)
        loopTask?.cancel()
        loopTask = Task { [weak self] in
            let clock = ContinuousClock()
            var nextTick = clock.now
            while !Task.isCancelled {
                nextTick = nextTick.advanced(by: period)
                // Re-bind weakly each frame so a discarded (mock) event loop can deinit
                guard let self else { return }
                await self.tick()
                try? await clock.sleep(until: nextTick)
            }
        }
    }

    private func stopLoop() {
        loopTask?.cancel()
        loopTask = nil
    }

    // Setter methods for mock setup
    func setMillisecondPerFrame(_ value: Int) {
        millisecondPerFrame = value
    }

    func setLogSpareTimeFrameInterval(_ value: Int) {
        logSpareTimeFrameInterval = value
    }

    func setFrameSpareTime(_ value: Double) {
        frameSpareTime = value
    }

}

extension EventLoop {
    static func mock() -> EventLoop {
        let mockEventLoop = EventLoop()
        Task {
            await mockEventLoop.setMillisecondPerFrame(50)
            await mockEventLoop.setLogSpareTimeFrameInterval(100)
            await mockEventLoop.setFrameSpareTime(100.0)
        }
        return mockEventLoop
    }
}
