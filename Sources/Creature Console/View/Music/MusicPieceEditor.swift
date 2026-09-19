import Common
import SwiftUI

/// Edits a piece in place: the timeline on top, the styles every section shares, then one card
/// per section. Nothing here generates; the owner decides when edits become audio (Apply).
struct MusicPieceEditor: View {
    @Binding var piece: MusicPiece
    let waveform: MusicWaveform
    let player: MusicPiecePlayer
    /// Length of the accepted voice take, when the piece is bound to a dialog.
    let dialogDurationMilliseconds: Int64?

    @State private var selectedSectionID: MusicSection.ID?
    @State private var globalPositiveStyles: [String] = []
    @State private var globalNegativeStyles: [String] = []

    private var problems: [String] {
        piece.refinementPlan().validationProblems(
            dialogDurationMilliseconds: dialogDurationMilliseconds)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            transport
            MusicTimelineView(
                piece: piece, waveform: waveform, player: player,
                selectedSectionID: $selectedSectionID,
                dialogDurationMilliseconds: dialogDurationMilliseconds)

            globalStyles

            ForEach(Array(piece.sections.indices), id: \.self) { index in
                sectionCard(at: index)
            }

            HStack {
                Button {
                    piece.insertSection(newSectionContent(), at: piece.sections.count)
                    selectedSectionID = piece.sections.last?.id
                } label: {
                    Label("Add Section", systemImage: "plus")
                }
                .buttonStyle(.glass)
                .disabled(piece.sections.count >= DialogLimits.maxMusicPlanChunks)
                Spacer()
                lengthLabel
            }

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
        .onAppear(perform: syncGlobalStyles)
        .onChange(
            of: piece.sections.map { $0.content.positiveStyles + ["|"] + $0.content.negativeStyles }
        ) { _, _ in
            syncGlobalStyles()
        }
        .onChange(of: globalPositiveStyles) { old, new in
            applyGlobalChange(old: old, new: new, negative: false)
        }
        .onChange(of: globalNegativeStyles) { old, new in
            applyGlobalChange(old: old, new: new, negative: true)
        }
    }

    // MARK: Transport

    private var transport: some View {
        HStack(spacing: 12) {
            Button {
                player.toggle()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.glassProminent)
            .disabled(!piece.hasAudio || player.loadedURL == nil)
            .keyboardShortcut(.space, modifiers: [])
            Button {
                player.stop()
            } label: {
                Image(systemName: "stop.fill")
            }
            .buttonStyle(.glass)
            .disabled(!piece.hasAudio || player.loadedURL == nil)
            TimelineView(.periodic(from: .now, by: 0.1)) { timeline in
                // Read on the tick so the label depends on the schedule (see MusicTimelineView).
                let position = player.isPlaying ? player.currentTime : player.pausedTime
                let _ = timeline.date
                Text(
                    "\(TimeHelper.formatDuration(position)) / \(TimeHelper.formatDuration(player.duration))"
                )
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
            }
            if let selectedSectionID,
                let index = piece.sections.firstIndex(where: { $0.id == selectedSectionID })
            {
                Button {
                    let start = Double(piece.sectionStartOffsets[index]) / 1_000
                    player.play(from: start)
                } label: {
                    Label(
                        "Play from \(piece.sections[index].name.isEmpty ? "section \(index + 1)" : piece.sections[index].name)",
                        systemImage: "play.circle")
                }
                .buttonStyle(.borderless)
                .disabled(
                    !piece.hasAudio || player.loadedURL == nil || piece.sections[index].span == nil)
            }
            Spacer()
            if piece.isDirty {
                Label(
                    "\(piece.dirtySections.count) section(s) changed", systemImage: "circle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            } else if piece.hasAudio {
                Label("Audio matches every section", systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
    }

    private var lengthLabel: some View {
        let planned = TimeHelper.formatDuration(Double(piece.plannedDurationMilliseconds) / 1_000)
        return Group {
            if let dialogDurationMilliseconds {
                Text(
                    "Piece \(planned) • dialog \(TimeHelper.formatDuration(Double(dialogDurationMilliseconds) / 1_000))"
                )
            } else {
                Text("Piece \(planned)")
            }
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
    }

    // MARK: Global styles

    private var globalStyles: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Every section").font(.subheadline.bold())
            MusicStyleChips(
                title: "Lean into", placeholder: "Add a style for the whole piece…",
                styles: $globalPositiveStyles, tint: .green)
            MusicStyleChips(
                title: "Avoid", placeholder: "Add a style to avoid everywhere…",
                styles: $globalNegativeStyles, tint: .red)
        }
        .padding(12)
        .panelCard(cornerRadius: 10)
    }

    private func syncGlobalStyles() {
        let positive = piece.globalPositiveStyles
        let negative = piece.globalNegativeStyles
        if positive != globalPositiveStyles { globalPositiveStyles = positive }
        if negative != globalNegativeStyles { globalNegativeStyles = negative }
    }

    private func applyGlobalChange(old: [String], new: [String], negative: Bool) {
        for style in Set(new).subtracting(old) {
            piece.addGlobalStyle(style, negative: negative)
        }
        for style in Set(old).subtracting(new) {
            piece.removeGlobalStyle(style, negative: negative)
        }
    }

    // MARK: Sections

    @ViewBuilder
    private func sectionCard(at index: Int) -> some View {
        let section = piece.sections[index]
        let isSelected = section.id == selectedSectionID
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("Name", text: nameBinding(at: index))
                    .textFieldStyle(.roundedBorder)
                    .font(.subheadline.bold())
                    .frame(maxWidth: 220)
                Text(
                    "at \(TimeHelper.formatDuration(Double(piece.sectionStartOffsets[index]) / 1_000))"
                )
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                if section.isDirty {
                    Label(section.span == nil ? "new" : "changed", systemImage: "circle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Spacer()
                sectionMenu(at: index)
            }

            TextField(
                "Directions — what this part sounds like, {hints} inline…",
                text: directionsBinding(at: index), axis: .vertical
            )
            .textFieldStyle(.roundedBorder)
            .lineLimit(1...4)

            HStack(spacing: 16) {
                durationField(at: index)
                Picker("Follows the piece", selection: contentBinding(at: index).contextAdherence) {
                    ForEach(MusicContextAdherence.allCases) { level in
                        Text(level.displayName).tag(level)
                    }
                }
                .fixedSize()
            }
            .font(.caption)

            MusicStyleChips(
                title: "Lean into", placeholder: "Add a style…",
                styles: contentBinding(at: index).positiveStyles, tint: .green)
            MusicStyleChips(
                title: "Avoid", placeholder: "Add a style to avoid…",
                styles: contentBinding(at: index).negativeStyles, tint: .red)

            if let reference = section.content.conditioningReference {
                HStack(spacing: 8) {
                    Label(
                        "Sounds like \(reference.songId == piece.songId ? "this piece" : "another take") \(TimeHelper.formatDuration(Double(reference.startMilliseconds) / 1_000))–\(TimeHelper.formatDuration(Double(reference.endMilliseconds) / 1_000))",
                        systemImage: "ear.badge.waveform")
                    Picker("", selection: strengthBinding(at: index)) {
                        ForEach(MusicConditionStrength.allCases) { strength in
                            Text(strength.displayName).tag(strength)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    Button("Clear") {
                        piece.sections[index].content = piece.sections[index].content
                            .unconditioned()
                    }
                    .buttonStyle(.borderless)
                }
                .font(.caption)
            }
        }
        .padding(12)
        .panelCard(
            cornerRadius: 10, tint: isSelected ? .accentColor : (section.isDirty ? .orange : nil)
        )
        .contentShape(Rectangle())
        .onTapGesture { selectedSectionID = section.id }
    }

    private func contentBinding(at index: Int) -> Binding<MusicGenerationChunk> {
        Binding(
            get: {
                piece.sections.indices.contains(index)
                    ? piece.sections[index].content
                    : MusicGenerationChunk(text: "", durationMilliseconds: 0)
            },
            set: { updated in
                guard piece.sections.indices.contains(index) else { return }
                piece.sections[index].content = updated
            })
    }

    private func nameBinding(at index: Int) -> Binding<String> {
        Binding(
            get: { piece.sections.indices.contains(index) ? piece.sections[index].name : "" },
            set: { name in
                guard piece.sections.indices.contains(index) else { return }
                let directions = piece.sections[index].directions
                piece.sections[index].setName(name, directions: directions)
            })
    }

    private func directionsBinding(at index: Int) -> Binding<String> {
        Binding(
            get: { piece.sections.indices.contains(index) ? piece.sections[index].directions : "" },
            set: { directions in
                guard piece.sections.indices.contains(index) else { return }
                let name = piece.sections[index].name
                piece.sections[index].setName(name, directions: directions)
            })
    }

    private func strengthBinding(at index: Int) -> Binding<MusicConditionStrength> {
        Binding(
            get: {
                piece.sections.indices.contains(index)
                    ? (piece.sections[index].content.conditionStrength ?? .medium) : .medium
            },
            set: { strength in
                guard piece.sections.indices.contains(index) else { return }
                piece.sections[index].content.conditionStrength = strength
            })
    }

    private func durationField(at index: Int) -> some View {
        let seconds = Binding<Double>(
            get: { Double(contentBinding(at: index).wrappedValue.durationMilliseconds) / 1_000 },
            set: {
                contentBinding(at: index).wrappedValue.durationMilliseconds = Int64(
                    ($0 * 1_000).rounded())
            })
        return HStack(spacing: 4) {
            Text("Length")
            TextField("s", value: seconds, format: .number.precision(.fractionLength(0...1)))
                .textFieldStyle(.roundedBorder)
                .frame(width: 64)
                .multilineTextAlignment(.trailing)
            Stepper("", value: seconds, in: 3...120, step: 0.5)
                .labelsHidden()
            Text("s")
        }
    }

    @ViewBuilder
    private func sectionMenu(at index: Int) -> some View {
        let section = piece.sections[index]
        Menu {
            Button {
                piece.insertSection(newSectionContent(after: index), at: index + 1)
            } label: {
                Label("Insert Section After", systemImage: "plus")
            }
            .disabled(piece.sections.count >= DialogLimits.maxMusicPlanChunks)
            Button {
                piece.splitSection(id: section.id, at: section.content.durationMilliseconds / 2)
            } label: {
                Label("Split in Half", systemImage: "rectangle.split.2x1")
            }
            .disabled(
                section.content.durationMilliseconds < DialogLimits.minMusicChunkMilliseconds * 2)
            if section.isDirty, section.committedContent != nil, section.span != nil {
                Button {
                    if let committed = section.committedContent {
                        piece.sections[index].content = committed
                    }
                } label: {
                    Label("Undo Changes to This Section", systemImage: "arrow.uturn.backward")
                }
            }
            Divider()
            Button {
                piece.moveSection(id: section.id, by: -1)
            } label: {
                Label("Move Up", systemImage: "arrow.up")
            }
            .disabled(index == 0)
            Button {
                piece.moveSection(id: section.id, by: 1)
            } label: {
                Label("Move Down", systemImage: "arrow.down")
            }
            .disabled(index == piece.sections.count - 1)
            Divider()
            Button(role: .destructive) {
                piece.removeSection(id: section.id)
                if selectedSectionID == section.id { selectedSectionID = nil }
            } label: {
                Label("Remove Section", systemImage: "trash")
            }
            .disabled(piece.sections.count == 1)
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .buttonStyle(.borderless)
        .fixedSize()
    }

    /// A new section inherits its neighbour's styles so the piece stays coherent.
    private func newSectionContent(after index: Int? = nil) -> MusicGenerationChunk {
        let neighbour =
            index.flatMap { piece.sections.indices.contains($0) ? piece.sections[$0].content : nil }
            ?? piece.sections.last?.content
        return MusicGenerationChunk(
            text: "", durationMilliseconds: 8_000,
            positiveStyles: neighbour?.positiveStyles ?? [],
            negativeStyles: neighbour?.negativeStyles ?? [],
            contextAdherence: neighbour?.contextAdherence ?? .high)
    }
}
