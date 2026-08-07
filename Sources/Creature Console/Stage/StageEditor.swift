import Common
import SwiftData
import SwiftUI

/// Authoring surface for a stage: where each creature sits and which way it faces.
///
/// Deliberately has no audio transport. Listening to a stage is the Spatial Stage window's job;
/// this is where the document gets written, and it works anywhere the app runs — including an iPad
/// standing next to the actual perches, which is where the heights are measured.
struct StageEditor: View {

    /// Open this stage rather than whichever was last selected. Set when arriving from the list,
    /// where the row you tapped is unambiguously the one you meant.
    var stageID: StageIdentifier?

    /// Open straight into a brand-new stage instead of the last-selected one.
    var createNew = false

    @Query(sort: \CreatureModel.name) private var creatures: [CreatureModel]
    /// Every saved dialog script, for the "Dialogs on This Stage" section — the *forward* link
    /// from a stage to the scenes that bind it. Filtered client-side by stage id.
    @Query(sort: \DialogScriptModel.title) private var dialogScriptModels: [DialogScriptModel]
    /// The local mirror the `stage-list` cache invalidation keeps current, so a stage saved on
    /// another device shows up here without anything being polled.
    @Query(sort: \StageModel.updatedAtMillis, order: .reverse) private var stageModels: [StageModel]
    @State private var store = StageStore()
    @State private var selectedCreatureID: CreatureIdentifier?
    @State private var isCreatingStage = false
    @State private var scriptToOpen: DialogScript? = nil
    @State private var isConfirmingDelete = false
    @State private var newStageTitle = ""

    private var stageCreatures: [StageCreature] {
        creatures.map { StageCreature(id: $0.id, name: $0.name, audioChannel: $0.audioChannel) }
    }

    private var placements: [StagePlacement] {
        store.stage?.placements ?? []
    }

    private var selectedPlacement: StagePlacement? {
        placements.first { $0.creatureID == selectedCreatureID }
    }

    private var offStageCreatures: [StageCreature] {
        let placed = Set(placements.map(\.creatureID))
        return stageCreatures.filter { $0.hasPlayableAudioLane && !placed.contains($0.id) }
    }

    private var extent: Float { StageLimits.coordinateLimit }

    var body: some View {
        Group {
            #if os(macOS)
                HSplitView {
                    map
                        .frame(minWidth: 480, minHeight: 420)
                        .padding()
                    inspector
                        .frame(minWidth: 290, idealWidth: 330, maxWidth: 380)
                }
            #else
                // On iPhone the map above a scrolling form reads better than a split, and on iPad
                // it still gives the map the top half of a big canvas.
                VStack(spacing: 0) {
                    map
                        .frame(minHeight: 260)
                        .padding()
                    Divider()
                    inspector
                }
            #endif
        }
        .navigationTitle(store.stage?.title.isEmpty == false ? store.stage!.title : "Stages")
        .task {
            store.noteKnownCreatures(stageCreatures)
            await store.load(selecting: stageID)
            // Arriving via "Create New" always prompts, even when the server already has stages —
            // otherwise the load would helpfully select an existing one and quietly ignore the ask.
            if createNew {
                isCreatingStage = true
            }
            ensureSelection()
        }
        .onChange(of: stageCreatures) { _, newValue in
            store.noteKnownCreatures(newValue)
        }
        .onChange(of: stageModels.map(\.updatedAtMillis)) { _, _ in
            store.syncStages(from: stageModels.map { $0.toDTO() })
        }
        .onChange(of: store.stage?.id) { _, _ in
            ensureSelection()
        }
        .toolbar {
            ToolbarItem {
                Button("New Stage", systemImage: "plus") { isCreatingStage = true }
            }
            ToolbarItem {
                Button("Save", systemImage: "square.and.arrow.down") {
                    Task { await store.save() }
                }
                .disabled(!store.canSave)
            }
        }
        .alert("New Stage", isPresented: $isCreatingStage) {
            TextField("Title", text: $newStageTitle)
            Button("Cancel", role: .cancel) { newStageTitle = "" }
            Button("Create") {
                let title = newStageTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                newStageTitle = ""
                guard !title.isEmpty else { return }
                Task { await store.create(title: title) }
            }
        } message: {
            Text("Name this physical arrangement — 'Mainstage', 'Travel', and so on.")
        }
        .sheet(item: $scriptToOpen) { script in
            NavigationStack {
                DialogScriptEditor(existing: script)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { scriptToOpen = nil }
                        }
                    }
            }
            #if os(macOS)
                .frame(minWidth: 760, minHeight: 640)
            #endif
        }
        .confirmationDialog(
            "Delete this stage?", isPresented: $isConfirmingDelete, titleVisibility: .visible
        ) {
            Button("Delete Stage", role: .destructive) {
                guard let id = store.stage?.id else { return }
                Task { await store.delete(id: id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Animations already rendered against it keep working, but it can't be used for new renders."
            )
        }
    }

    @ViewBuilder
    private var map: some View {
        if store.stage != nil {
            StageMapView(
                placements: placements,
                selectedCreatureID: $selectedCreatureID,
                displayName: displayName(for:),
                onMove: { id, x, z in
                    store.updatePlacement(creatureID: id) {
                        $0.x = x
                        $0.z = z
                    }
                },
                onRemove: { id in
                    store.removeCreature(id: id)
                    if selectedCreatureID == id { ensureSelection() }
                }
            )
        } else {
            ContentUnavailableView {
                Label("No Stage Selected", systemImage: "square.on.square.dashed")
            } description: {
                Text(
                    "A stage says where each creature physically sits and which way it faces, so the server can aim heads at whoever is speaking."
                )
            } actions: {
                Button("New Stage…") { isCreatingStage = true }
                    .buttonStyle(.glassProminent)
            }
        }
    }

    private var inspector: some View {
        Form {
            stageSection
            if store.stage != nil {
                dialogsSection
                placementSection
                offStageSection
                audioSection
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Dialogs on this stage

    /// Scripts whose saved binding points at the selected stage.
    private var boundScripts: [DialogScriptModel] {
        guard let id = store.stage?.id.uuidString.lowercased() else { return [] }
        return dialogScriptModels.filter { $0.stageIdString == id }
    }

    private enum ScriptRenderStatus {
        case unrendered
        case current
        case stale
    }

    /// What state a bound script's renders are in, joined from the server's staleness report.
    /// The report lists *animations rendered against this stage*; a bound script with no entry
    /// there has never been rendered with the stage — the state that otherwise looks like
    /// "saving my stage did nothing".
    private func renderStatus(for script: DialogScriptModel) -> ScriptRenderStatus {
        guard let report = store.animationStaleness else { return .unrendered }
        let scriptID = script.id.uuidString.lowercased()
        let entries = report.items.filter { $0.sourceScriptID.lowercased() == scriptID }
        if entries.isEmpty { return .unrendered }
        return entries.contains(where: \.isStale) ? .stale : .current
    }

    @ViewBuilder
    private var dialogsSection: some View {
        Section("Dialogs on This Stage") {
            if boundScripts.isEmpty {
                Text(
                    "No dialog scripts bind this stage yet. Pick it in a script's Stage section to give that scene head aiming."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                ForEach(boundScripts) { script in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(script.title.isEmpty ? "(untitled)" : script.title)
                            statusLabel(renderStatus(for: script))
                        }
                        Spacer()
                        Button("Open") {
                            scriptToOpen = script.toDTO()
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func statusLabel(_ status: ScriptRenderStatus) -> some View {
        switch status {
        case .unrendered:
            Label("Not rendered with this stage yet", systemImage: "circle.dashed")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .current:
            Label("Rendered — up to date", systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(.green)
        case .stale:
            Label(
                "Rendered before this stage last moved — re-render",
                systemImage: "clock.badge.exclamationmark"
            )
            .font(.caption)
            .foregroundStyle(.orange)
        }
    }

    private var stageSection: some View {
        Section("Stage") {
            Picker("Stage", selection: stageSelection) {
                Text("None").tag(StageIdentifier?.none)
                ForEach(store.stages) { stage in
                    Text(stage.title.isEmpty ? "(untitled)" : stage.title).tag(Optional(stage.id))
                }
            }
            .disabled(store.isSaving)

            if case .failed(let message) = store.loadState {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }

            if let staleness = store.animationStaleness, let summary = staleness.stalenessSummary {
                Label(summary, systemImage: "clock.badge.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .help(
                        "These were rendered before this stage last changed. Re-render them to pick up the new positions."
                    )
            } else if let staleness = store.animationStaleness, staleness.count > 0 {
                Label(
                    "\(staleness.count) animation(s) rendered on this stage, all current",
                    systemImage: "checkmark.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if let notice = store.remoteChangeNotice {
                Label(notice, systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if store.hasUnsavedChanges {
                Label(
                    "Unsaved changes. Saving marks animations rendered on this stage as out of date.",
                    systemImage: "pencil.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if let problem = store.validationProblem {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }

            if let error = store.saveError {
                Label(error, systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            HStack {
                Button("Revert") { store.revert() }
                    .disabled(!store.hasUnsavedChanges || store.isSaving)
                Spacer()
                if store.stage != nil {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        isConfirmingDelete = true
                    }
                    .disabled(store.isSaving)
                }
            }
        }
    }

    @ViewBuilder
    private var placementSection: some View {
        if let placement = selectedPlacement {
            Section(displayName(for: placement)) {
                LabeledContent("Audio channel", value: "\(placement.audioChannel)")

                // Height leads, and is never hidden behind a disclosure: elevation is what tells
                // the audience which creature is being addressed.
                LabeledContent("Height") {
                    Text("\(placement.y, specifier: "%+.2f") m").monospacedDigit()
                }
                Slider(value: binding(placement.creatureID, \.y), in: -extent...extent)
                Text("Relative to your ears — a bird on a low perch sits negative.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                LabeledContent("Left / right") {
                    Text("\(placement.x, specifier: "%+.2f") m").monospacedDigit()
                }
                Slider(value: binding(placement.creatureID, \.x), in: -extent...extent)

                LabeledContent("Front / back") {
                    Text("\(placement.z, specifier: "%+.2f") m").monospacedDigit()
                }
                Slider(value: binding(placement.creatureID, \.z), in: -extent...extent)

                LabeledContent("Facing") {
                    Text("\(placement.yaw, specifier: "%+.0f")°").monospacedDigit()
                }
                Slider(value: binding(placement.creatureID, \.yaw), in: -180...180)
                HStack {
                    Text(facingDescription(placement.yaw))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Face Me") {
                        store.updatePlacement(creatureID: placement.creatureID) {
                            $0.yaw = StageFrame.headingTowardListener(
                                from: (x: $0.x, y: $0.y, z: $0.z))
                        }
                    }
                    .buttonStyle(.borderless)
                }

                LabeledContent("Gain") {
                    Text("\(Int(placement.gain * 100))%")
                }
                Slider(value: binding(placement.creatureID, \.gain), in: 0...1.5)

                Toggle(
                    "Muted",
                    isOn: Binding(
                        get: { selectedPlacement?.isMuted ?? false },
                        set: { newValue in
                            store.updatePlacement(creatureID: placement.creatureID) {
                                $0.isMuted = newValue
                            }
                        }
                    )
                )
            }
        } else {
            Section("Creature") {
                Text("Select a creature on the stage to set its position and facing.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var offStageSection: some View {
        if !offStageCreatures.isEmpty {
            Section("Not on This Stage") {
                ForEach(offStageCreatures) { creature in
                    Button {
                        store.addCreature(creature)
                        selectedCreatureID = creature.id
                    } label: {
                        Label("Add \(creature.name)", systemImage: "plus.circle")
                    }
                }
            }
        }
    }

    private var audioSection: some View {
        Section("Spatial Mix") {
            Stepper(
                "\(store.stage?.audio.monitoringDelayMilliseconds ?? 0) ms RTP buffer",
                value: audioBinding(\.monitoringDelayMilliseconds, default: 10),
                in: 10...250,
                step: 10)
            Stepper(
                "\(store.stage?.audio.commonPlayoutDelayMilliseconds ?? 0) ms RTCP playout",
                value: audioBinding(\.commonPlayoutDelayMilliseconds, default: 20),
                in: 20...250,
                step: 10)
            LabeledContent("BGM") {
                Text("\(Int((store.stage?.audio.backgroundMusicGain ?? 0) * 100))%")
            }
            Slider(value: audioBinding(\.backgroundMusicGain, default: 0.7), in: 0...1)
            LabeledContent("Room") {
                Text("\(Int((store.stage?.audio.reverbBlend ?? 0) * 100))%")
            }
            Slider(value: audioBinding(\.reverbBlend, default: 0.08), in: 0...0.5)

            Text("Used by the Spatial Stage monitor when it renders this stage.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    private func displayName(for placement: StagePlacement) -> String {
        if let live = stageCreatures.first(where: { $0.id == placement.creatureID })?.name,
            !live.isEmpty
        {
            return live
        }
        return placement.creatureName.isEmpty ? placement.creatureID : placement.creatureName
    }

    private func ensureSelection() {
        if !placements.contains(where: { $0.creatureID == selectedCreatureID }) {
            selectedCreatureID = placements.first?.creatureID
        }
    }

    private func binding(
        _ id: CreatureIdentifier, _ keyPath: WritableKeyPath<StagePlacement, Float>
    ) -> Binding<Float> {
        Binding(
            get: { placements.first(where: { $0.creatureID == id })?[keyPath: keyPath] ?? 0 },
            set: { value in
                store.updatePlacement(creatureID: id) { $0[keyPath: keyPath] = value }
            }
        )
    }

    private func audioBinding<Value>(
        _ keyPath: WritableKeyPath<StageAudioSettings, Value>, default fallback: Value
    ) -> Binding<Value> {
        Binding(
            get: { store.stage?.audio[keyPath: keyPath] ?? fallback },
            set: { value in
                guard var stage = store.stage else { return }
                stage.audio[keyPath: keyPath] = value
                store.stage = stage
            }
        )
    }

    private var stageSelection: Binding<StageIdentifier?> {
        Binding(
            get: { store.stage?.id },
            set: { store.select($0) }
        )
    }

    /// Plain-language reading of a heading, so nobody has to hold the sign convention in their head
    /// while dragging a slider.
    private func facingDescription(_ yaw: Float) -> String {
        switch yaw {
        case -22.5...22.5: "Facing you"
        case 22.5..<67.5: "Facing your right, toward you"
        case 67.5...112.5: "Facing your right"
        case 112.5..<157.5: "Facing your right, away"
        case -67.5..<(-22.5): "Facing your left, toward you"
        case -112.5...(-67.5): "Facing your left"
        case -157.5..<(-112.5): "Facing your left, away"
        default: "Facing away from you"
        }
    }
}
