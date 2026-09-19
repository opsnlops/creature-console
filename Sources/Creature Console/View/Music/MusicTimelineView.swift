import Common
import SwiftUI

/// The piece as a strip of time: its waveform underneath, its sections as blocks over it, a
/// playhead, and the dialog's end when the piece is bound to one. Click to select a section
/// and move the playhead there; drag the border between two sections to move time from one to
/// the other, or the end of the last section to change the piece's length.
struct MusicTimelineView: View {
    @Binding var piece: MusicPiece
    let waveform: MusicWaveform
    let player: MusicPiecePlayer
    @Binding var selectedSectionID: MusicSection.ID?
    let dialogDurationMilliseconds: Int64?

    private let height: CGFloat = 132
    private let rulerHeight: CGFloat = 18
    /// How close to a border a press must land to grab it, in points.
    private let grabTolerance: CGFloat = 7

    /// A border being dragged: the index of the section it ends, and the durations of that
    /// section (and the next, when there is one) when the drag began.
    private struct BorderDrag {
        let index: Int
        let leadingDuration: Int64
        let trailingDuration: Int64?
    }
    @State private var borderDrag: BorderDrag?
    @State private var hoveredBorder: Int?

    /// The strip covers the longest of: audio on file, the planned piece, the dialog.
    private var totalSeconds: Double {
        let planned = Double(piece.plannedDurationMilliseconds) / 1_000
        let dialog = Double(dialogDurationMilliseconds ?? 0) / 1_000
        return max(waveform.duration, planned, dialog, 1)
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            TimelineView(.animation(minimumInterval: 1 / 30, paused: !player.isPlaying)) {
                timeline in
                // The playhead is read here, on the tick, so the Canvas below depends on the
                // schedule. Reading it inside the Canvas alone left the drawing stale: the
                // player's position isn't an observed property, and a Canvas whose inputs
                // look unchanged is not redrawn.
                let playhead = player.isPlaying ? player.currentTime : player.pausedTime
                let tick = timeline.date
                Canvas { context, size in
                    _ = tick
                    draw(in: &context, size: size, playhead: playhead)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if borderDrag == nil,
                            let index = border(near: value.startLocation.x, width: width)
                        {
                            borderDrag = BorderDrag(
                                index: index,
                                leadingDuration: piece.sections[index].content.durationMilliseconds,
                                trailingDuration: piece.sections.indices.contains(index + 1)
                                    ? piece.sections[index + 1].content.durationMilliseconds : nil)
                        }
                        if let borderDrag {
                            let delta = Int64(
                                (Double(value.translation.width / width) * totalSeconds * 1_000)
                                    .rounded())
                            resize(borderDrag, by: delta)
                        }
                    }
                    .onEnded { value in
                        if borderDrag != nil {
                            borderDrag = nil
                            return
                        }
                        let seconds = Double(value.location.x / width) * totalSeconds
                        select(at: seconds)
                    }
            )
            .onContinuousHover { phase in
                switch phase {
                case .active(let point):
                    hoveredBorder = border(near: point.x, width: width)
                case .ended:
                    hoveredBorder = nil
                }
            }
        }
        .frame(height: height)
        .accessibilityLabel("Timeline")
    }

    /// The border under `x`, as the index of the section it ends, or nil. The end of the last
    /// section counts; the start of the piece does not.
    private func border(near x: CGFloat, width: CGFloat) -> Int? {
        var cursor: Int64 = 0
        for (index, section) in piece.sections.enumerated() {
            cursor += section.content.durationMilliseconds
            let borderX = self.x(forSeconds: Double(cursor) / 1_000, width: width)
            if abs(borderX - x) <= grabTolerance { return index }
        }
        return nil
    }

    /// Move a border by `delta` ms from where the drag began: the section before it grows by
    /// that much and the one after shrinks, both kept within a section's legal length. The
    /// last border has nothing after it, so it just changes the piece's length. Snapped to
    /// tenths of a second, which is what the length fields show.
    private func resize(_ drag: BorderDrag, by delta: Int64) {
        let minimum = DialogLimits.minMusicChunkMilliseconds
        let maximum = DialogLimits.maxMusicChunkMilliseconds
        var change = (delta / 100) * 100
        change = max(change, minimum - drag.leadingDuration)
        change = min(change, maximum - drag.leadingDuration)
        if let trailing = drag.trailingDuration {
            change = min(change, trailing - minimum)
            change = max(change, trailing - maximum)
        }
        guard piece.sections.indices.contains(drag.index) else { return }
        piece.sections[drag.index].content.durationMilliseconds = drag.leadingDuration + change
        if let trailing = drag.trailingDuration, piece.sections.indices.contains(drag.index + 1) {
            piece.sections[drag.index + 1].content.durationMilliseconds = trailing - change
        }
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

    private func draw(in context: inout GraphicsContext, size: CGSize, playhead: Double) {
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

            // The border after this section, brighter when it can be grabbed.
            let borderIndex = piece.sections.firstIndex(where: { $0.id == section.id })
            let isGrabbed = borderDrag?.index == borderIndex || hoveredBorder == borderIndex
            var border = Path()
            border.move(to: CGPoint(x: rect.maxX + 1, y: stripTop))
            border.addLine(to: CGPoint(x: rect.maxX + 1, y: size.height))
            context.stroke(
                border, with: .color(isGrabbed ? .accentColor : .secondary.opacity(0.5)),
                lineWidth: isGrabbed ? 3 : 1)

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
            let xHead = x(forSeconds: min(playhead, waveform.duration), width: width)
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
