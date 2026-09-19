import Common
import SwiftUI

/// The piece as a strip of time: its waveform underneath, its sections as blocks over it, a
/// playhead, and the dialog's end when the piece is bound to one. Click to select a section
/// and move the playhead there.
struct MusicTimelineView: View {
    let piece: MusicPiece
    let waveform: MusicWaveform
    let player: MusicPiecePlayer
    @Binding var selectedSectionID: MusicSection.ID?
    let dialogDurationMilliseconds: Int64?

    private let height: CGFloat = 132
    private let rulerHeight: CGFloat = 18

    /// The strip covers the longest of: audio on file, the planned piece, the dialog.
    private var totalSeconds: Double {
        let planned = Double(piece.plannedDurationMilliseconds) / 1_000
        let dialog = Double(dialogDurationMilliseconds ?? 0) / 1_000
        return max(waveform.duration, planned, dialog, 1)
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            TimelineView(.animation(minimumInterval: 1 / 30, paused: !player.isPlaying)) { _ in
                Canvas { context, size in
                    draw(in: &context, size: size)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        let seconds = Double(value.location.x / width) * totalSeconds
                        select(at: seconds)
                    }
            )
        }
        .frame(height: height)
        .accessibilityLabel("Timeline")
    }

    private func x(forSeconds seconds: Double, width: CGFloat) -> CGFloat {
        CGFloat(seconds / totalSeconds) * width
    }

    private func select(at seconds: Double) {
        let milliseconds = Int64(seconds * 1_000)
        var cursor: Int64 = 0
        for section in piece.sections {
            let end = cursor + section.content.durationMilliseconds
            if milliseconds >= cursor && milliseconds < end {
                selectedSectionID = section.id
                break
            }
            cursor = end
        }
        if seconds <= waveform.duration {
            player.seek(to: seconds)
        }
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let width = size.width
        let stripTop = rulerHeight
        let stripHeight = size.height - rulerHeight

        // Ruler
        let tick = tickInterval(for: totalSeconds)
        var mark = 0.0
        while mark <= totalSeconds {
            let x = x(forSeconds: mark, width: width)
            context.stroke(
                Path {
                    $0.move(to: CGPoint(x: x, y: rulerHeight - 4))
                    $0.addLine(to: CGPoint(x: x, y: rulerHeight))
                },
                with: .color(.secondary.opacity(0.6)), lineWidth: 1)
            context.draw(
                Text(TimeHelper.formatDuration(mark)).font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary),
                at: CGPoint(x: x + 3, y: rulerHeight / 2 - 2), anchor: .leading)
            mark += tick
        }

        // Waveform (audio on file)
        if !waveform.peaks.isEmpty {
            let audioWidth = x(forSeconds: waveform.duration, width: width)
            let binWidth = audioWidth / CGFloat(waveform.peaks.count)
            let middle = stripTop + stripHeight / 2
            var bars = Path()
            for (index, peak) in waveform.peaks.enumerated() {
                let barHeight = max(1, CGFloat(peak) * (stripHeight / 2 - 6))
                let barX = CGFloat(index) * binWidth
                bars.addRect(
                    CGRect(
                        x: barX, y: middle - barHeight, width: max(0.5, binWidth - 0.5),
                        height: barHeight * 2))
            }
            context.fill(bars, with: .color(.secondary.opacity(0.35)))
        }

        // Sections (planned)
        var cursor: Int64 = 0
        for section in piece.sections {
            let start = Double(cursor) / 1_000
            let end = Double(cursor + section.content.durationMilliseconds) / 1_000
            cursor += section.content.durationMilliseconds
            let rect = CGRect(
                x: x(forSeconds: start, width: width) + 1, y: stripTop + 2,
                width: max(
                    2, x(forSeconds: end, width: width) - x(forSeconds: start, width: width) - 2),
                height: stripHeight - 4)
            let shape = Path(roundedRect: rect, cornerRadius: 6)
            let isSelected = section.id == selectedSectionID
            let fill: Color = isSelected ? .accentColor.opacity(0.28) : .primary.opacity(0.06)
            context.fill(shape, with: .color(fill))
            let stroke: Color =
                section.isDirty ? .orange : (isSelected ? .accentColor : .secondary.opacity(0.4))
            context.stroke(shape, with: .color(stroke), lineWidth: section.isDirty ? 1.5 : 1)

            let name = section.name.isEmpty ? "Section" : section.name
            let label = section.isDirty ? "\(name) •" : name
            context.draw(
                Text(label).font(.caption.bold()).foregroundStyle(.primary),
                at: CGPoint(x: rect.minX + 6, y: rect.maxY - 10), anchor: .leading)
            context.draw(
                Text(TimeHelper.formatDuration(end - start)).font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary),
                at: CGPoint(x: rect.minX + 6, y: rect.minY + 10), anchor: .leading)
        }

        // Dialog end
        if let dialogDurationMilliseconds, dialogDurationMilliseconds > 0 {
            let xEnd = x(forSeconds: Double(dialogDurationMilliseconds) / 1_000, width: width)
            var line = Path()
            line.move(to: CGPoint(x: xEnd, y: stripTop))
            line.addLine(to: CGPoint(x: xEnd, y: size.height))
            context.stroke(
                line, with: .color(.purple.opacity(0.8)),
                style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            context.draw(
                Text("dialog ends").font(.caption2).foregroundStyle(.purple),
                at: CGPoint(x: xEnd - 4, y: stripTop + 8), anchor: .trailing)
        }

        // Playhead
        if waveform.duration > 0 {
            let xHead = x(forSeconds: min(player.currentTime, waveform.duration), width: width)
            var head = Path()
            head.move(to: CGPoint(x: xHead, y: 0))
            head.addLine(to: CGPoint(x: xHead, y: size.height))
            context.stroke(head, with: .color(.red), lineWidth: 1.5)
        }
    }

    private func tickInterval(for seconds: Double) -> Double {
        switch seconds {
        case ..<20: 2
        case ..<60: 5
        case ..<180: 15
        case ..<600: 30
        default: 60
        }
    }
}
