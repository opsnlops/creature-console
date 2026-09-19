import Common
import SwiftUI

/// Edits a composition plan section by section: what each one sounds like, how long it runs,
/// the styles to lean into and away from, and whether it should sound like a prior take.
/// Validation mirrors the server's, so the message here is the message the server would send.
struct MusicPlanEditor: View {
    @Binding var plan: MusicCompositionPlan
    /// Length of the accepted voice take, once learned; the plan must cover it.
    let dialogDurationMilliseconds: Int64?
    /// The take this plan builds on, if any — shown so a reference section has a name.
    let referenceTake: MusicReferenceTake?

    private var offsets: [Int64] { plan.chunkStartOffsets }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(plan.chunks.indices), id: \.self) { index in
                sectionRow(at: index)
            }

            HStack {
                Button {
                    appendSection()
                } label: {
                    Label("Add Section", systemImage: "plus")
                }
                .buttonStyle(.glass)
                .disabled(plan.chunks.count >= DialogLimits.maxMusicPlanChunks)
                Spacer()
                totalLabel
            }

            let problems = plan.validationProblems(
                dialogDurationMilliseconds: dialogDurationMilliseconds)
            if !problems.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(problems, id: \.self) { problem in
                        Label(problem, systemImage: "exclamationmark.triangle")
                    }
                }
                .font(.caption)
                .foregroundStyle(.orange)
            }
        }
    }

    private var totalLabel: some View {
        let total = TimeHelper.formatDuration(Double(plan.totalDurationMilliseconds) / 1_000)
        return Group {
            if let dialogDurationMilliseconds {
                let dialog = TimeHelper.formatDuration(Double(dialogDurationMilliseconds) / 1_000)
                Text("Plan \(total) • dialog \(dialog)")
            } else {
                Text("Plan \(total)")
            }
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func sectionRow(at index: Int) -> some View {
        let start = offsets.indices.contains(index) ? offsets[index] : 0
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Section \(index + 1)")
                    .font(.subheadline.bold())
                Text("at \(TimeHelper.formatDuration(Double(start) / 1_000))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                sectionMenu(at: index)
            }
            switch plan.chunks[index] {
            case .audioReference(let range):
                referenceRow(range)
            case .generation:
                generationRow(at: index)
            }
        }
        .padding(12)
        .panelCard(cornerRadius: 10)
    }

    @ViewBuilder
    private func referenceRow(_ range: MusicAudioRange) -> some View {
        let name =
            referenceTake?.songId == range.songId
            ? (referenceTake?.label ?? "a prior take") : "a prior take"
        Label(
            "Re-render \(TimeHelper.formatDuration(Double(range.startMilliseconds) / 1_000))–\(TimeHelper.formatDuration(Double(range.endMilliseconds) / 1_000)) of \(name)",
            systemImage: "waveform.badge.magnifyingglass"
        )
        .font(.subheadline)
        Text(
            "The model re-plays this span from the earlier take. It comes out close to the original, not sample-exact."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        Text(range.songId)
            .font(.caption2.monospaced())
            .foregroundStyle(.tertiary)
            .textSelection(.enabled)
    }

    @ViewBuilder
    private func generationRow(at index: Int) -> some View {
        let chunk = generationBinding(at: index)
        TextField(
            "[Section] {direction} — what this part sounds like…", text: chunk.text,
            axis: .vertical
        )
        .textFieldStyle(.roundedBorder)
        .lineLimit(1...4)

        HStack(spacing: 16) {
            durationField(chunk.durationMilliseconds)
            Picker("Follows plan", selection: chunk.contextAdherence) {
                ForEach(MusicContextAdherence.allCases) { level in
                    Text(level.displayName).tag(level)
                }
            }
            .fixedSize()
        }
        .font(.caption)

        MusicStyleChips(
            title: "Lean into", placeholder: "Add a style…", styles: chunk.positiveStyles,
            tint: .green)
        MusicStyleChips(
            title: "Avoid", placeholder: "Add a style to avoid…", styles: chunk.negativeStyles,
            tint: .red)

        if let reference = chunk.wrappedValue.conditioningReference {
            HStack(spacing: 8) {
                Label(
                    "Sounds like \(referenceName(reference))",
                    systemImage: "ear.badge.waveform")
                Picker("", selection: strengthBinding(chunk)) {
                    ForEach(MusicConditionStrength.allCases) { strength in
                        Text(strength.displayName).tag(strength)
                    }
                }
                .labelsHidden()
                .fixedSize()
                Button("Clear") {
                    var updated = chunk.wrappedValue
                    updated.conditioningReference = nil
                    updated.conditionStrength = nil
                    chunk.wrappedValue = updated
                }
                .buttonStyle(.borderless)
            }
            .font(.caption)
        }
    }

    private func durationField(_ milliseconds: Binding<Int64>) -> some View {
        let seconds = Binding<Double>(
            get: { Double(milliseconds.wrappedValue) / 1_000 },
            set: { milliseconds.wrappedValue = Int64(($0 * 1_000).rounded()) })
        return HStack(spacing: 4) {
            Text("Length")
            TextField(
                "s", value: seconds, format: .number.precision(.fractionLength(0...1))
            )
            .textFieldStyle(.roundedBorder)
            .frame(width: 64)
            .multilineTextAlignment(.trailing)
            Stepper("", value: seconds, in: 3...120, step: 0.5)
                .labelsHidden()
            Text("s")
        }
    }

    private func strengthBinding(_ chunk: Binding<MusicGenerationChunk>)
        -> Binding<MusicConditionStrength>
    {
        Binding(
            get: { chunk.wrappedValue.conditionStrength ?? .medium },
            set: { chunk.wrappedValue.conditionStrength = $0 })
    }

    private func referenceName(_ range: MusicAudioRange) -> String {
        let span =
            "\(TimeHelper.formatDuration(Double(range.startMilliseconds) / 1_000))–\(TimeHelper.formatDuration(Double(range.endMilliseconds) / 1_000))"
        if referenceTake?.songId == range.songId, let label = referenceTake?.label {
            return "\(label) (\(span))"
        }
        return "a prior take (\(span))"
    }

    /// A binding into a generation chunk. Writes through only while the chunk is still a
    /// generation chunk at that index; a stale write after a delete is dropped, not crashed.
    private func generationBinding(at index: Int) -> Binding<MusicGenerationChunk> {
        Binding(
            get: {
                if plan.chunks.indices.contains(index),
                    case .generation(let chunk) = plan.chunks[index]
                {
                    return chunk
                }
                return MusicGenerationChunk(text: "", durationMilliseconds: 0)
            },
            set: { updated in
                guard plan.chunks.indices.contains(index),
                    case .generation = plan.chunks[index]
                else { return }
                plan.chunks[index] = .generation(updated)
            })
    }

    @ViewBuilder
    private func sectionMenu(at index: Int) -> some View {
        Menu {
            Button {
                insertSection(after: index)
            } label: {
                Label("Insert Section After", systemImage: "plus")
            }
            .disabled(plan.chunks.count >= DialogLimits.maxMusicPlanChunks)
            if case .generation = plan.chunks[index] {
                Button {
                    splitSection(at: index)
                } label: {
                    Label("Split in Half", systemImage: "rectangle.split.2x1")
                }
                .disabled(
                    plan.chunks[index].durationMilliseconds < DialogLimits.minMusicChunkMilliseconds
                        * 2)
            }
            Divider()
            Button {
                move(index, by: -1)
            } label: {
                Label("Move Up", systemImage: "arrow.up")
            }
            .disabled(index == 0)
            Button {
                move(index, by: 1)
            } label: {
                Label("Move Down", systemImage: "arrow.down")
            }
            .disabled(index == plan.chunks.count - 1)
            Divider()
            Button(role: .destructive) {
                plan.chunks.remove(at: index)
            } label: {
                Label("Remove Section", systemImage: "trash")
            }
            .disabled(plan.chunks.count == 1)
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .buttonStyle(.borderless)
        .fixedSize()
    }

    private func appendSection() {
        plan.chunks.append(.generation(newSection()))
    }

    private func insertSection(after index: Int) {
        plan.chunks.insert(.generation(newSection()), at: index + 1)
    }

    /// A new section inherits the styles of its neighbour so the piece stays coherent.
    private func newSection() -> MusicGenerationChunk {
        let neighbour = plan.chunks.reversed().compactMap { chunk -> MusicGenerationChunk? in
            if case .generation(let generation) = chunk { return generation }
            return nil
        }.first
        return MusicGenerationChunk(
            text: "", durationMilliseconds: 8_000,
            positiveStyles: neighbour?.positiveStyles ?? [],
            negativeStyles: neighbour?.negativeStyles ?? [],
            contextAdherence: neighbour?.contextAdherence ?? .high)
    }

    private func splitSection(at index: Int) {
        guard case .generation(var first) = plan.chunks[index] else { return }
        let total = first.durationMilliseconds
        var second = first
        first.durationMilliseconds = total / 2
        second.durationMilliseconds = total - first.durationMilliseconds
        plan.chunks[index] = .generation(first)
        plan.chunks.insert(.generation(second), at: index + 1)
    }

    private func move(_ index: Int, by delta: Int) {
        let target = index + delta
        guard plan.chunks.indices.contains(target) else { return }
        plan.chunks.swapAt(index, target)
    }
}

/// A row of removable style chips with a field to add another. Enter commits; commas split.
struct MusicStyleChips: View {
    let title: String
    let placeholder: String
    @Binding var styles: [String]
    let tint: Color

    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            MusicChipFlow(spacing: 6) {
                ForEach(styles, id: \.self) { style in
                    HStack(spacing: 4) {
                        Text(style)
                        Button {
                            styles.removeAll { $0 == style }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption2.bold())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(style)")
                    }
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .glassEffect(.regular.tint(tint.opacity(0.25)), in: .capsule)
                }
                TextField(placeholder, text: $draft)
                    .textFieldStyle(.plain)
                    .font(.caption)
                    .frame(minWidth: 120)
                    .onSubmit(commit)
                    .disabled(styles.count >= DialogLimits.maxMusicStyles)
            }
        }
    }

    private func commit() {
        let additions =
            draft
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.utf8.count <= DialogLimits.maxMusicStyleBytes }
        for addition in additions where !styles.contains(addition) {
            guard styles.count < DialogLimits.maxMusicStyles else { break }
            styles.append(addition)
        }
        draft = ""
    }
}

/// Lays chips out left to right, wrapping to new lines as the width runs out.
struct MusicChipFlow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        return arrange(width: width, subviews: subviews).size
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        let arrangement = arrange(width: bounds.width, subviews: subviews)
        for (subview, origin) in zip(subviews, arrangement.origins) {
            subview.place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                proposal: .unspecified)
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: maxX, height: y + rowHeight), origins)
    }
}
