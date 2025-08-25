import Common
import Foundation
import OSLog
import SwiftUI

/// This EventLoop runs on a background thread!
///
/// This means that updates to the UI need to be dispatched to the main thread. This can be done like this:
///
/// DispatchQueue.main.async {
///    doAThing();
/// }
actor EventLoop {

    // Make a singleton out of this
    static let shared = EventLoop()

    private var timer: DispatchSourceTimer?
    private(set) var number_of_frames: Int64 = 0

    // Access other actors as needed - no stored references to avoid isolation issues

    /**
     Keep track of how much spare time we have in each frame. I have nothing but very fast Macs, so this should rarely be
     an issue, but if it is, I'd like for it to be shown to the status bar
     */

    var frameSpareTime: Double = 0  // Updated value (no longer @Published since actors can't have @Published)
    var localFrameSpareTime: Double = 0  // Updated every loop

    @AppStorage("eventLoopMillisecondsPerFrame") var millisecondPerFrame: Int = 20
    @AppStorage("logSpareTimeFrameInterval") var logSpareTimeFrameInterval: Int = 1000
    @AppStorage("logSpareTime") var logSpareTime: Bool = false
    @AppStorage("updateSpareTimeStatusInterval") var updateSpareTimeStatusInterval: Int = 20

    private let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "EventLoop")
    private let numberFormatter = NumberFormatter()


    /// Start up all of the things
    init() {

        self.frameSpareTime = 100.0

        // Configure the number formatter
        numberFormatter.numberStyle = .decimal
        numberFormatter.maximumFractionDigits = 2
        numberFormatter.minimumFractionDigits = 2

        Task {
            await startTimer()
        }

        logger.info("event loop started")
    }

    deinit {
        timer?.cancel()
        timer = nil
        logger.info("event loop stopped")
    }


    /// Main Event Loop
    private func update() {

        // Keep metrics on how long the the loop takes
        let startTime = DispatchTime.now()


        // Update our metrics
        number_of_frames += 1

        // Tell the `JoystickManager` it's time to poll
        Task {
            await JoystickManager.shared.poll()
        }

        // Tell the creature manager we've set everything up for it
        Task {
            await CreatureManager.shared.onEventLoopTick()
        }


        // Update metrics
        let endTime = DispatchTime.now()
        let elapsedTime = endTime.uptimeNanoseconds - startTime.uptimeNanoseconds

        // Figure out our spare time this cycle
        let elapsedTimeInMilliseconds = Double(elapsedTime) / 1_000_000.0
        let frameTimeInNanoseconds = Double(millisecondPerFrame) * 1_000_000.0
        localFrameSpareTime = (1 - (Double(elapsedTime) / frameTimeInNanoseconds)) * 100.0

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


    private func startTimer() {
        logger.info("Starting event loop at \(self.millisecondPerFrame)ms per frame")

        timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
        timer?.setEventHandler { [weak self] in
            guard let self = self else { return }
            Task {
                await self.update()
            }
        }
        timer?.schedule(
            deadline: .now(), repeating: .milliseconds(millisecondPerFrame), leeway: .nanoseconds(0)
        )
        timer?.resume()
    }

    private func stopTimer() {
        timer?.cancel()
        timer = nil
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
