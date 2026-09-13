import SwiftUI

/// How much bigger (or smaller) than the system text size the Communicator shows its
/// words. The system's Dynamic Type setting is always the starting point — Settings ›
/// Accessibility on the phone, Text Size on the Mac — and this steps from there, the way
/// Messages' View › Make Text Bigger does. April: "I'm old and I need bigger fonts some days."
enum CommunicatorTextSize {
    static let storageKey = "textSizeSteps"
    static let range = -2...4

    /// The system size moved by `steps`, clamped to what Dynamic Type offers.
    static func size(from system: DynamicTypeSize, steps: Int) -> DynamicTypeSize {
        let all = DynamicTypeSize.allCases
        guard let index = all.firstIndex(of: system) else { return system }
        let moved = min(max(index + steps, 0), all.count - 1)
        return all[moved]
    }

    static func clamped(_ steps: Int) -> Int {
        min(max(steps, range.lowerBound), range.upperBound)
    }

    static func label(for steps: Int) -> String {
        switch steps {
        case 0: "System size"
        case ..<0: "\(-steps) smaller"
        default: "\(steps) bigger"
        }
    }
}

/// Applies the Communicator's text size on top of whatever the system says.
struct CommunicatorTextSizeModifier: ViewModifier {
    @Environment(\.dynamicTypeSize) private var systemSize
    @AppStorage(CommunicatorTextSize.storageKey) private var steps = 0

    func body(content: Content) -> some View {
        content.dynamicTypeSize(CommunicatorTextSize.size(from: systemSize, steps: steps))
    }
}

extension View {
    func communicatorTextSize() -> some View {
        modifier(CommunicatorTextSizeModifier())
    }
}

#if os(macOS)
    /// View › Make Text Bigger / Smaller / Actual Size, with Messages' shortcuts.
    struct TextSizeCommands: Commands {
        @AppStorage(CommunicatorTextSize.storageKey) private var steps = 0

        var body: some Commands {
            CommandGroup(after: .toolbar) {
                Button("Make Text Bigger") {
                    steps = CommunicatorTextSize.clamped(steps + 1)
                }
                .keyboardShortcut("+", modifiers: .command)
                .disabled(steps >= CommunicatorTextSize.range.upperBound)

                Button("Make Text Smaller") {
                    steps = CommunicatorTextSize.clamped(steps - 1)
                }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(steps <= CommunicatorTextSize.range.lowerBound)

                Button("Actual Size") { steps = 0 }
                    .keyboardShortcut("0", modifiers: .command)
                    .disabled(steps == 0)

                Divider()
            }
        }
    }
#endif
