
import SwiftUI
import Common

struct BarChart: View {
    @Binding var data: [UInt8]
    @Environment(\.colorScheme) var colorScheme
    var barSpacing: CGFloat = 2.0
    var maxValue: UInt8 = 255

    var rainbowColors: [Color] {
        let baseColors: [Color] = [
            .red, .orange, .yellow, .green, .blue, .indigo, .purple
        ]

        switch colorScheme {
        case .dark:
            return baseColors.map { $0.opacity(0.8) }
        default:
            return baseColors
        }
    }

    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .bottom, spacing: barSpacing) {
                ForEach(0..<data.count, id: \.self) { index in
                    VStack {
                        Spacer()
                        RoundedRectangle(cornerRadius: 4)
                            .fill(rainbowColors[index % rainbowColors.count])
                            .frame(height: geometry.size.height * CGFloat(data[index]) / CGFloat(maxValue))
                    }
                }
            }
        }
    }
}

struct BarChart_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            BarChartPreviewWrapper()
                .previewDisplayName("Default Bar Chart with Random Data")

            BarChartPreviewWrapper(barSpacing: 4.0)
                .previewDisplayName("Custom Bar Chart with Random Data")
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
