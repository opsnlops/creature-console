import SwiftUI

struct VoltageMeterView: View {

    var title: String   // New: Title for the chart
    var minValue: Double
    var maxValue: Double
    var currentValue: Double

    private var angleRange: Double {
        return 180.0 // The range of the meter's arc (180 degrees for half-circle)
    }

    private var currentAngle: Double {
        // Calculate the angle for the needle based on the current value
        let normalizedValue = (currentValue - minValue) / (maxValue - minValue)
        return normalizedValue * angleRange - angleRange / 2
    }

    var body: some View {
        VStack {
            // Title for the meter
            Text(title)
                .font(.system(size: 16))
                .padding(.bottom, 10)

            ZStack {
                // The arc of the voltage meter
                ArcShape()
                    .stroke(Color.black, lineWidth: 10)
                    .frame(width: 200, height: 100) // Adjust the frame size

                // The needle
                NeedleShape()
                    .stroke(Color.red, lineWidth: 3)
                    .frame(width: 4, height: 100) // Needle dimensions
                    .rotationEffect(Angle(degrees: currentAngle))
                    .offset(y: 50) // Adjust the needle center to the bottom of the arc

                // Voltage labels
                HStack {
                    Text("\(Int(minValue))")
                    Spacer()
                    Text("\(Int(maxValue))")
                }
                .font(.system(size: 18))
                .frame(width: 200)
                .offset(y: 70) // Adjust label position
            }

            // Current voltage display at the bottom
            Text("\(String(format: "%.3f", currentValue))v")
                .font(.system(size: 24))
                .padding(.top, 10)
        }
        .padding()
    }
}

struct ArcShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(center: CGPoint(x: rect.midX, y: rect.maxY),
                    radius: rect.width / 2,
                    startAngle: Angle(degrees: 180),  // Left side of arc
                    endAngle: Angle(degrees: 0),      // Right side of arc
                    clockwise: false)
        return path
    }
}

struct NeedleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
        return path
    }
}

#Preview {
    VoltageMeterView(title: "Sensor 1", minValue: 0, maxValue: 150, currentValue: 75)
}

