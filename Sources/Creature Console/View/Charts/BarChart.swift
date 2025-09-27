import Common
import SwiftUI

struct BarChart: View {
    @Binding var data: [UInt8]
    @Environment(\.colorScheme) var colorScheme
    var barSpacing: CGFloat = 2.0
    var maxValue: UInt8 = 255

    // Liquid Glass-friendly tweaks
    var cornerRadius: CGFloat = 6
    var peakGlowThreshold: CGFloat = 0.92  // When near max, add a soft glow
    var showTrack: Bool = false  // Optional faint track behind bars

    private var rainbowColors: [Color] {
        let baseColors: [Color] = [.red, .orange, .yellow, .green, .blue, .indigo, .purple]
        switch colorScheme {
        case .dark:
            return baseColors.map { $0.opacity(0.85) }
        default:
            return baseColors
        }
    }

    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .bottom, spacing: barSpacing) {
                ForEach(0..<data.count, id: \.self) { index in
                    let color = rainbowColors[index % rainbowColors.count]
                    let normalized = min(max(CGFloat(data[index]) / CGFloat(maxValue), 0), 1)

                    ZStack(alignment: .bottom) {
                        if showTrack {
                            // Optional subtle track showing full scale
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .fill(Color.white.opacity(colorScheme == .dark ? 0.06 : 0.08))
                        }

                        // The bar itself
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(color)
                            .frame(height: geometry.size.height * normalized)
                            // Sheen highlight (paint-only)
                            .overlay(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.18),
                                        Color.white.opacity(0.04),
                                        .clear,
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                                .blendMode(.screen)
                            )
                            // Hairline edge for definition
                            .overlay(
                                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
                            )
                            // Conditional glow when peaking
                            .shadow(
                                color: color.opacity(normalized >= peakGlowThreshold ? 0.35 : 0.0),
                                radius: normalized >= peakGlowThreshold ? 10 : 0,
                                x: 0, y: 0
                            )
                    }
                    // Anchor each bar container to the bottom so bars grow upward
                    .frame(height: geometry.size.height, alignment: .bottom)
                }
            }
            // Avoid implicit animations on frequent updates
            .animation(nil, value: data)
        }
    }
}

struct BarChart_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            BarChartPreviewWrapper()
                .previewDisplayName("Default Bar Chart with Random Data")

            BarChartPreviewWrapper(barSpacing: 4.0)
                .previewDisplayName("Custom Bar Chart with Random Data and Spacing")
        }
    }
}

struct BarChartPreviewWrapper: View {
    @State private var randomData: [UInt8] = (0..<6).map { _ in UInt8.random(in: 0...255) }
    var barSpacing: CGFloat = 2.0

    var body: some View {
        BarChart(data: $randomData, barSpacing: barSpacing)
            .frame(height: 200)
            .previewLayout(.sizeThatFits)
            .padding()
    }
}
