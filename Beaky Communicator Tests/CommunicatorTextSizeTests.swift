import SwiftUI
import Testing

@testable import Beaky_Communicator

@Suite("Communicator text size")
struct CommunicatorTextSizeTests {
    @Test("Steps move from the system size and stop at the ends of Dynamic Type")
    func stepsFromSystemSize() {
        #expect(CommunicatorTextSize.size(from: .large, steps: 0) == .large)
        #expect(CommunicatorTextSize.size(from: .large, steps: 1) == .xLarge)
        #expect(CommunicatorTextSize.size(from: .large, steps: -1) == .medium)
        // A phone already on the biggest accessibility size stays there.
        #expect(
            CommunicatorTextSize.size(from: .accessibility5, steps: 4) == .accessibility5)
        #expect(CommunicatorTextSize.size(from: .xSmall, steps: -2) == .xSmall)
    }

    #if os(macOS)
        @Test("On the Mac the words really get bigger: text styles there ignore Dynamic Type")
        @MainActor func macScalesRenderedText() {
            func width(scale: Double) -> Int {
                let renderer = ImageRenderer(
                    content: Text("Beaky, the front door was just unlocked.")
                        .communicatorFont(.body)
                        .environment(\.communicatorTextScale, scale))
                return renderer.cgImage?.width ?? -1
            }
            let system = width(scale: CommunicatorTextSize.scale(steps: 0))
            let bigger = width(scale: CommunicatorTextSize.scale(steps: 4))
            #expect(system > 0)
            #expect(Double(bigger) > Double(system) * 1.4)
        }
    #endif

    @Test("The stepper stays within its range and says what it did")
    func clampingAndLabels() {
        #expect(CommunicatorTextSize.clamped(9) == 4)
        #expect(CommunicatorTextSize.clamped(-9) == -2)
        #expect(CommunicatorTextSize.label(for: 0) == "System size")
        #expect(CommunicatorTextSize.label(for: 2) == "2 bigger")
        #expect(CommunicatorTextSize.label(for: -1) == "1 smaller")
    }
}
