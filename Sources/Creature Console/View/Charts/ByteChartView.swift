import Common
import SwiftUI

struct ByteChartView: View {
    var data: [UInt8]
    var color: Color = .accentColor
    var lineWidth: CGFloat = 1.5
    var backgroundOpacity: Double = 0.5

    var body: some View {
        GeometryReader { geometry in
            let widthPerPoint = geometry.size.width / CGFloat(data.count)

            Path { path in
                path.move(
                    to: CGPoint(
                        x: 0,
                        y: geometry.size.height - geometry.size.height * CGFloat(data[0]) / 255.0))

                for (index, value) in data.enumerated() {
                    let x = CGFloat(index) * widthPerPoint
                    let y = geometry.size.height - geometry.size.height * CGFloat(value) / 255.0
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            .stroke(color, lineWidth: lineWidth)

            Path { path in
                path.move(to: CGPoint(x: 0, y: geometry.size.height))

                for (index, value) in data.enumerated() {
                    let x = CGFloat(index) * widthPerPoint
                    let y = geometry.size.height - geometry.size.height * CGFloat(value) / 255.0
                    path.addLine(to: CGPoint(x: x, y: y))
                }

                path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height))
                path.closeSubpath()
            }
            .fill(
                LinearGradient(
                    gradient: Gradient(colors: [color.opacity(0.9), color.opacity(0.6)]),
                    startPoint: .top, endPoint: .bottom))
        }
        .background {
            #if os(macOS)
                Color(NSColor.windowBackgroundColor).opacity(backgroundOpacity)
            #elseif os(iOS)
                Color(UIColor.systemBackground).opacity(backgroundOpacity)
            #endif
        }
    }
}

struct ByteChartView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            let numberPoints = 100
            let height = 80.0

            let data0: [UInt8] = (0..<numberPoints).map { _ in UInt8.random(in: 0...255) }
            let data1: [UInt8] = (0..<numberPoints).map { _ in UInt8.random(in: 0...255) }
            let data2: [UInt8] = (0..<numberPoints).map { _ in UInt8.random(in: 0...255) }
            let data3: [UInt8] = (0..<numberPoints).map { _ in UInt8.random(in: 0...255) }
            let data4: [UInt8] = (0..<numberPoints).map { _ in UInt8.random(in: 0...255) }
            let data5: [UInt8] = (0..<numberPoints).map { _ in UInt8.random(in: 0...255) }
            let data6: [UInt8] = (0..<numberPoints).map { _ in UInt8.random(in: 0...255) }

            VStack {
                ByteChartView(data: data0, color: .red)
                    .frame(height: height)
                ByteChartView(data: data1, color: .blue)
                    .frame(height: height)
                ByteChartView(data: data2, color: .green)
                    .frame(height: height)
                ByteChartView(data: data3, color: .purple)
                    .frame(height: height)
                ByteChartView(data: data4, color: .orange)
                    .frame(height: height)
                ByteChartView(data: data5, color: .yellow)
                    .frame(height: height)
                ByteChartView(data: data6)
                    .frame(height: height)
            }
        }
    }
}
