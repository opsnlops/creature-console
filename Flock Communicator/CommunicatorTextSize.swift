import SwiftUI

/// How much bigger (or smaller) than the system text size the Communicator shows its
/// words. The system's setting is always the starting point — Accessibility › Text Size on
/// either platform — and this steps from there, the way Messages' View › Make Text Bigger
/// does. April: "I'm old and I need bigger fonts some days."
///
/// On iOS a step is a Dynamic Type size. On the Mac SwiftUI's text styles are fixed and
/// `dynamicTypeSize` is ignored, so a step is a 12 % scale applied to each style's system
/// point size instead.
enum CommunicatorTextSize {
    static let storageKey = "textSizeSteps"
    static let range = -2...4
    static let macStepScale = 1.12

    /// The system size moved by `steps`, clamped to what Dynamic Type offers.
    static func size(from system: DynamicTypeSize, steps: Int) -> DynamicTypeSize {
        let all = DynamicTypeSize.allCases
        guard let index = all.firstIndex(of: system) else { return system }
        let moved = min(max(index + steps, 0), all.count - 1)
        return all[moved]
    }

    /// The Mac's multiplier for `steps`: 1 at the system size, about 1.57 at the top.
    static func scale(steps: Int) -> Double {
        pow(macStepScale, Double(clamped(steps)))
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

private struct CommunicatorTextScaleKey: EnvironmentKey {
    static let defaultValue = 1.0
}

extension EnvironmentValues {
    /// The Mac's text multiplier; always 1 on iOS, where Dynamic Type does the scaling.
    var communicatorTextScale: Double {
        get { self[CommunicatorTextScaleKey.self] }
        set { self[CommunicatorTextScaleKey.self] = newValue }
    }
}

/// Applies the Communicator's text size on top of whatever the system says.
struct CommunicatorTextSizeModifier: ViewModifier {
    @Environment(\.dynamicTypeSize) private var systemSize
    @AppStorage(CommunicatorTextSize.storageKey) private var steps = 0

    func body(content: Content) -> some View {
        #if os(macOS)
            content.environment(\.communicatorTextScale, CommunicatorTextSize.scale(steps: steps))
        #else
            content.dynamicTypeSize(CommunicatorTextSize.size(from: systemSize, steps: steps))
        #endif
    }
}

/// A text style at the Communicator's size.
struct CommunicatorFontModifier: ViewModifier {
    let style: Font.TextStyle
    let weight: Font.Weight
    @Environment(\.communicatorTextScale) private var scale

    func body(content: Content) -> some View {
        #if os(macOS)
            content.font(
                .system(
                    size: NSFont.preferredFont(forTextStyle: style.nsTextStyle).pointSize * scale,
                    weight: weight))
        #else
            content.font(.system(style, weight: weight))
        #endif
    }
}

extension View {
    func communicatorTextSize() -> some View {
        modifier(CommunicatorTextSizeModifier())
    }

    /// Use instead of `.font(.body)` and friends so the Mac scales too.
    func communicatorFont(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> some View {
        modifier(CommunicatorFontModifier(style: style, weight: weight))
    }
}

#if os(macOS)
    extension Font.TextStyle {
        var nsTextStyle: NSFont.TextStyle {
            switch self {
            case .largeTitle: .largeTitle
            case .title: .title1
            case .title2: .title2
            case .title3: .title3
            case .headline: .headline
            case .subheadline: .subheadline
            case .body: .body
            case .callout: .callout
            case .footnote: .footnote
            case .caption: .caption1
            case .caption2: .caption2
            @unknown default: .body
            }
        }
    }

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
