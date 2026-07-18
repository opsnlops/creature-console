import Common
import SwiftUI

/// The dialog enrichment shown under a creature's servo waveforms when the animation was rendered
/// from a dialog. Two truthful, self-contained pieces:
///
/// 1. A **mouth-activity ribbon** — the creature's embedded mouth cues baked into per-frame servo
///    openness (via the shared `MouthShape.bakeFrames`, the same path the client's old Rhubarb
///    import used) and drawn with the *same* `ByteChartView` as the servo rows, so it lines up
///    with them and reads exactly like the physical mouth. Silence (shape X → 0) shows as the flat
///    gaps between speech. Hover (macOS) / scrub (iOS) reads out the timecode and — when the render
///    carries word-level alignment (#56) — the **word being spoken**, else the mouth shape.
/// 2. The **script lines** this creature speaks, filtered from the rendered script.
struct TrackDialogSection: View {

    let lipsync: DialogProvenance.LipsyncTrack
    /// Word-level alignment for this lane (#56); nil for older renders.
    var wordTrack: DialogProvenance.WordTrack? = nil
    let scriptLines: [DialogProvenance.ScriptLine]
    let millisecondsPerFrame: UInt32
    let frameCount: Int
    var color: Color = .accentColor
    /// The label-gutter width and row height are matched to `TrackViewer`'s rows so the ribbon
    /// aligns horizontally with the servo waveforms above it.
    var labelWidth: CGFloat = 80
    var height: CGFloat = 34

    @State private var showScript = false

    private var durationSeconds: Double {
        Double(frameCount) * Double(millisecondsPerFrame) / 1000.0
    }

    var body: some View {
        // Baked here, directly from the current cues — always fresh when this section's inputs
        // change. The scrub cursor lives in `MouthRibbonChart`'s own state, so hovering never
        // re-evaluates this body and the bake (and the chart's Path) are not rebuilt while
        // scrubbing.
        let bakedFrames = lipsync.mouthFrames(
            millisecondsPerFrame: millisecondsPerFrame, frameCount: frameCount)

        return VStack(alignment: .leading, spacing: 6) {
            MouthRibbonChart(
                frames: bakedFrames,
                lipsync: lipsync,
                wordTrack: wordTrack,
                durationSeconds: durationSeconds,
                color: color,
                labelWidth: labelWidth,
                height: height)
            scriptDisclosure
        }
        .padding(.vertical, 4)
    }

    // MARK: - Script

    @ViewBuilder
    private var scriptDisclosure: some View {
        if !scriptLines.isEmpty {
            DisclosureGroup(isExpanded: $showScript) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(scriptLines) { line in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("\(line.index + 1).")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Text(line.text)
                                .font(.callout)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(.top, 4)
            } label: {
                Label(
                    "\(lipsync.name)'s lines (\(scriptLines.count))",
                    systemImage: "text.quote"
                )
                .font(.subheadline)
            }
            .padding(.leading, labelWidth)
        }
    }
}

/// The interactive mouth-activity ribbon: label gutter, the baked-frame chart, and the scrub
/// readout. Owns the cursor state so hovering only re-evaluates this small view — the
/// (potentially thousands-of-frames) `ByteChartView` receives unchanged `frames` and is not
/// re-rendered, and the parent doesn't re-bake.
private struct MouthRibbonChart: View {
    let frames: [UInt8]
    let lipsync: DialogProvenance.LipsyncTrack
    var wordTrack: DialogProvenance.WordTrack? = nil
    let durationSeconds: Double
    var color: Color
    var labelWidth: CGFloat
    var height: CGFloat

    /// Cursor position as a fraction (0…1) across the chart, or nil when not hovering/scrubbing.
    @State private var cursorFraction: Double? = nil

    private var cursorSeconds: Double? {
        guard let f = cursorFraction, durationSeconds > 0 else { return nil }
        return min(max(f, 0), 1) * durationSeconds
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Default HStack spacing (not 0) to match TrackViewer's servo rows exactly, so the
            // ribbon chart lines up horizontally with the waveforms above it.
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Mouth", systemImage: "mouth.fill")
                        .font(.caption)
                        .labelStyle(.titleAndIcon)
                    Text("from dialog")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(width: labelWidth, alignment: .leading)
                .padding()

                chart
                    .frame(height: height)
            }
            readout
        }
    }

    @ViewBuilder
    private var chart: some View {
        if frames.isEmpty {
            Color.clear
        } else {
            GeometryReader { geo in
                ByteChartView(data: frames, color: color)
                    .overlay(alignment: .leading) {
                        if let f = cursorFraction {
                            Rectangle()
                                .fill(.primary.opacity(0.6))
                                .frame(width: 1)
                                .offset(x: min(max(f, 0), 1) * geo.size.width)
                        }
                    }
                    .contentShape(.rect)
                    #if os(macOS)
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                cursorFraction = location.x / geo.size.width
                            case .ended:
                                cursorFraction = nil
                            }
                        }
                    #else
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { cursorFraction = $0.location.x / geo.size.width }
                                .onEnded { _ in cursorFraction = nil }
                        )
                    #endif
            }
        }
    }

    @ViewBuilder
    private var readout: some View {
        HStack(spacing: 8) {
            if let seconds = cursorSeconds {
                Label(
                    TimeHelper.formatDuration(seconds, withTenths: true), systemImage: "clock"
                )
                .font(.caption.monospacedDigit())
                cursorDetail(at: seconds)
            } else if let span = lipsync.timeSpan {
                Text(
                    "Speaks \(TimeHelper.formatDuration(span.lowerBound, withTenths: true))–\(TimeHelper.formatDuration(span.upperBound, withTenths: true))"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.leading, labelWidth)
        .frame(minHeight: 16, alignment: .leading)
    }

    /// What's happening at the cursor: the spoken **word** when the render carries word alignment
    /// (#56), otherwise the mouth shape. A word wins because it's what the author is looking for;
    /// a gap between words (or an older render) falls back to the mouth state.
    @ViewBuilder
    private func cursorDetail(at seconds: Double) -> some View {
        if let word = wordTrack?.word(at: seconds) {
            Text("“\(word)”")
                .font(.caption.weight(.medium))
        } else if let shape = lipsync.shape(at: seconds) {
            Text(MouthShape.isSilent(shape) ? "silent" : "mouth \(shape)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
