import XCTest
import SwiftUI
import ViewInspector
@testable import Common
@testable import Creature_Console


final class BottomToolBarViewTests: XCTestCase {

    func testBottomToolBarViewDisplaysCorrectTexts() throws {
        let view = BottomToolBarView()

        let totalFramesText = try view.inspect().find(text: "Server Frame: \(view.serverCounters.systemCounters.totalFrames)").string()
        XCTAssertEqual(totalFramesText, "Server Frame: \(view.serverCounters.systemCounters.totalFrames)")

        let restRequestsText = try view.inspect().find(text: "Rest Req: \(view.serverCounters.systemCounters.restRequestsProcessed)").string()
        XCTAssertEqual(restRequestsText, "Rest Req: \(view.serverCounters.systemCounters.restRequestsProcessed)")

        let streamedFramesText = try view.inspect().find(text: "Streamed: \(view.serverCounters.systemCounters.framesStreamed)").string()
        XCTAssertEqual(streamedFramesText, "Streamed: \(view.serverCounters.systemCounters.framesStreamed)")

        let spareTimeText = try view.inspect().find(text: "Spare Time: \(String(format: "%.2f", view.eventLoop.frameSpareTime))%").string()
        XCTAssertEqual(spareTimeText, "Spare Time: \(String(format: "%.2f", view.eventLoop.frameSpareTime))%")

        let stateText = try view.inspect().find(text: "State: \(view.appState.currentActivity)").string()
        XCTAssertEqual(stateText, "State: \(view.appState.currentActivity)")
    }

    func testBottomToolBarViewDisplaysCorrectImages() throws {
        let view = BottomToolBarView()

        // Arrow Circle Path Image
        let arrowImage = try view.inspect().find(ViewType.Image.self).actualImage().name()
        XCTAssertEqual(arrowImage, "arrow.circlepath")

        // Rainbow Image when streaming
        view.statusLights.streaming = true
        let rainbowImage = try view.inspect().findAll(ViewType.Image.self)[1].actualImage().name()
        XCTAssertEqual(rainbowImage, "rainbow")

        // Antenna Image when DMX is active
        view.statusLights.dmx = true
        let antennaImage = try view.inspect().findAll(ViewType.Image.self)[2].actualImage().name()
        XCTAssertEqual(antennaImage, "antenna.radiowaves.left.and.right.circle.fill")
    }
}
