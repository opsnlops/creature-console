import Common
import Foundation
import OSLog
import SwiftData
import SwiftUI

/// Top-level editor for a `DialogScript`. Operates on a local mutable `@State` copy of the
/// script (struct value semantics, mirroring `FixtureEditor`). Live, debounced validation
/// runs against the server's `/validate` endpoint; once the script is saved, the listen /
/// export and render panels appear inline so the author can audition and render without
/// bouncing back through the table.
struct DialogScriptEditor: View {

    /// How the editor was reached, which decides the render affordance.
    enum Mode {
        /// Opened from the Dialogs section to author/render a script. Shows the full render
        /// panel (fresh render with storage/autoplay/title).
        case standalone
        /// Opened from an animation that was already rendered from this script. Shows a
        /// "Re-render in Place" control instead of a fresh-render panel.
        case animationLinked
    }

    private let mode: Mode

    private let logger = Logger(
        subsystem: "io.opsnlops.CreatureConsole", category: "DialogScriptEditor")

    /// `true` until the first successful save in create-new flow, then flipped to `false` so
    /// the preview + render panels light up in place.
    @State private var createNew: Bool
    /// The script as it exists on the server now (after the most recent save). Used for
    /// dirty detection and to decide whether a render can go by `script_id` (provenance).
    @State private var original: DialogScript
    @State private var script: DialogScript

    @State private var validation: DialogScriptValidationDTO? = nil
    @State private var validateTask: Task<Void, Never>? = nil
    @State private var isValidating = false

    @State private var isSaving = false
    @State private var savingMessage = ""

    @State private var showErrorAlert = false
    @State private var alertTitle = "Error"
    @State private var alertMessage = ""

    @State private var savedBanner = false

    /// Take chosen in the preview panel, reused by the render panel.
    @State private var selectedGenerationId: DialogGenerationIdentifier? = nil

    @Environment(\.dismiss) private var dismiss

    @Query(sort: \CreatureModel.name, order: .forward)
    private var creatures: [CreatureModel]

    private let server = CreatureServerClient.shared

    init(createNew: Bool) {
        let template = DialogScript.newEmpty()
        self.mode = .standalone
        _createNew = State(initialValue: createNew)
        _original = State(initialValue: template)
        _script = State(initialValue: template)
    }

    init(existing: DialogScript, mode: Mode = .standalone) {
        self.mode = mode
        _createNew = State(initialValue: false)
        _original = State(initialValue: existing)
        _script = State(initialValue: existing)
    }

    /// True when the in-memory script differs from the last-saved server copy.
    private var isDirty: Bool { script != original }

    /// Pass a script id to the render panel only when the saved server copy matches what's on
    /// screen, so render-by-id provenance can't capture stale turns.
    private var renderScriptId: DialogScriptIdentifier? {
        (!createNew && !isDirty) ? original.id : nil
    }

    private var canAddTurn: Bool { script.turns.count < DialogLimits.maxTurns }

    var body: some View {
        ScrollView {
            GlassEffectContainer(spacing: 16) {
                VStack(alignment: .leading, spacing: 16) {
                    detailsSection
                    turnsSection
                    validationBanner
                    // Preview + render work on the in-memory turns, so they're available before the
                    // first save (an unsaved scene renders inline). They appear once there's a turn.
                    if !script.turns.isEmpty {
                        DialogPreviewPanel(
                            turns: script.turns, title: script.title,
                            selectedGenerationId: $selectedGenerationId)
                        switch mode {
                        case .standalone:
                            DialogRenderPanel(
                                scriptId: renderScriptId,
                                turns: script.turns,
                                selectedGenerationId: selectedGenerationId,
                                defaultTitle: script.title)
                        case .animationLinked:
                            // This script already has a rendered animation; offer an in-place
                            // re-render instead of a fresh one. Requires a saved (non-dirty) script
                            // so the re-render picks up the latest turns server-side.
                            if !createNew {
                                DialogRerenderButton(
                                    scriptId: original.id,
                                    title: script.title,
                                    disabled: isDirty,
                                    disabledHint: isDirty
                                        ? "Save your edits first so the re-render includes them."
                                        : nil
                                )
                            }
                        }
                    }
                    Spacer(minLength: 40)
                }
                .padding()
            }
        }
        .navigationTitle(
            createNew ? "New Dialog" : (script.title.isEmpty ? "Dialog" : script.title)
        )
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: save) {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .disabled(isSaving || !canSave)
            }
            if !createNew {
                ToolbarItem(placement: .secondaryAction) {
                    Button(role: .destructive, action: deleteScript) {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .alert(alertTitle, isPresented: $showErrorAlert) {
            Button("OK") {}
        } message: {
            Text(alertMessage)
        }
        .overlay(alignment: .top) {
            if isSaving {
                Text(savingMessage)
                    .font(.title3)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .glassEffect(.regular, in: .capsule)
                    .padding(.top, 12)
                    .transition(.opacity)
            } else if savedBanner {
                Label("Saved", systemImage: "checkmark.circle.fill")
                    .font(.title3)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .glassEffect(.regular.tint(.green.opacity(0.4)), in: .capsule)
                    .padding(.top, 12)
                    .transition(.opacity)
            }
        }
        .task { await runValidation(for: script) }
        .onChange(of: script) { _, newValue in
            scheduleValidation(for: newValue)
        }
        .onChange(of: script.turns) {
            // The server's preview cache key is sha256(turns), so any turn change (text,
            // creature, add/remove/reorder) orphans the selected take — asking for it under
            // the new key would 404. Fall back to "latest / server decides".
            selectedGenerationId = nil
        }
    }

    // MARK: - Sections

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Details").font(.title2.bold())
            HStack(alignment: .firstTextBaseline) {
                Text("Title").font(.title3).frame(width: 80, alignment: .leading)
                VStack(alignment: .trailing, spacing: 4) {
                    TextField("Scene title", text: $script.title)
                        .textFieldStyle(.roundedBorder)
                        .font(.title3)
                    characterCount(script.title.count, limit: DialogLimits.maxTitle)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Notes").font(.title3).foregroundStyle(.secondary)
                TextEditor(text: $script.notes)
                    .font(.title3)
                    .frame(minHeight: 90)
                    .contentMargins(16, for: .scrollContent)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8).stroke(.quaternary)
                    )
                characterCount(script.notes.count, limit: DialogLimits.maxNotes)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(20)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }

    private var turnsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Turns").font(.title2.bold())
                Spacer()
                Text("\(script.turns.count)/\(DialogLimits.maxTurns)")
                    .font(.subheadline)
                    .foregroundStyle(script.turns.count > DialogLimits.maxTurns ? .red : .secondary)
            }

            if script.turns.isEmpty {
                Text(
                    "Add a turn for each line of dialog. Order matters — it's both the speaking order and the order the voices react to one another. You can include ElevenLabs tags like [excited] or [whispering] in the text."
                )
                .font(.body)
                .foregroundStyle(.secondary)
            }

            ForEach($script.turns) { $turn in
                turnRow(turn: $turn)
            }

            Button {
                addTurn()
            } label: {
                Label("Add Turn", systemImage: "plus.circle")
            }
            .disabled(!canAddTurn)
        }
        .padding(20)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }

    @ViewBuilder
    private func turnRow(turn: Binding<DialogScriptTurn>) -> some View {
        let id = turn.wrappedValue.id
        let index = script.turns.firstIndex(where: { $0.id == id }) ?? 0
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Turn \(index + 1)").font(.title3.bold())
                Spacer()
                creaturePicker(selection: turn.creatureId)
                Button {
                    moveTurn(id: id, by: -1)
                } label: {
                    Image(systemName: "arrow.up")
                }
                .disabled(index == 0)
                .buttonStyle(.borderless)
                Button {
                    moveTurn(id: id, by: 1)
                } label: {
                    Image(systemName: "arrow.down")
                }
                .disabled(index == script.turns.count - 1)
                .buttonStyle(.borderless)
                Button(role: .destructive) {
                    removeTurn(id: id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }

            TextEditor(text: turn.text)
                .font(.title3)
                .frame(minHeight: 88)
                .contentMargins(16, for: .scrollContent)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))

            characterCount(turn.wrappedValue.text.count, limit: DialogLimits.maxTurnText)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(16)
        .background(.background.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }

    private func creaturePicker(selection: Binding<CreatureIdentifier>) -> some View {
        Picker("Creature", selection: selection) {
            Text("Select creature…").tag("")
            ForEach(creatures) { creature in
                Text(creature.name).tag(creature.id)
            }
            // Preserve an unknown / missing creature id so editing doesn't silently drop it.
            if !selection.wrappedValue.isEmpty,
                !creatures.contains(where: { $0.id == selection.wrappedValue })
            {
                Text("Unknown (\(selection.wrappedValue.prefix(8)))")
                    .tag(selection.wrappedValue)
            }
        }
        .labelsHidden()
        .frame(maxWidth: 220)
    }

    @ViewBuilder
    private var validationBanner: some View {
        if let validation, !createNew || !script.turns.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    if isValidating {
                        ProgressView().controlSize(.small)
                        Text("Validating…").font(.caption).foregroundStyle(.secondary)
                    } else if validation.valid {
                        Label("Valid", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                            .font(.subheadline)
                    } else {
                        Label("Not valid yet", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.subheadline)
                    }
                    Spacer()
                }
                ForEach(validation.errorMessages, id: \.self) { msg in
                    Label(msg, systemImage: "xmark.octagon")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                ForEach(validation.missingCreatureIds, id: \.self) { cid in
                    Label(
                        "Creature not registered: \(cid)", systemImage: "person.fill.questionmark"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .glassEffect(.regular, in: .rect(cornerRadius: 12))
        }
    }

    private func characterCount(_ count: Int, limit: Int) -> some View {
        Text("\(count)/\(limit)")
            .font(.caption2)
            .foregroundStyle(count > limit ? .red : .secondary)
    }

    // MARK: - Derived

    private var localLimitProblem: String? {
        if script.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Title cannot be empty."
        }
        if script.title.count > DialogLimits.maxTitle {
            return "Title is too long (max \(DialogLimits.maxTitle) characters)."
        }
        if script.notes.count > DialogLimits.maxNotes {
            return "Notes are too long (max \(DialogLimits.maxNotes) characters)."
        }
        if script.turns.isEmpty {
            return "Add at least one turn."
        }
        if script.turns.count > DialogLimits.maxTurns {
            return "Too many turns (max \(DialogLimits.maxTurns))."
        }
        if script.turns.contains(where: { $0.text.count > DialogLimits.maxTurnText }) {
            return "A turn's text is too long (max \(DialogLimits.maxTurnText) characters)."
        }
        return nil
    }

    private var canSave: Bool { localLimitProblem == nil }

    // MARK: - Turn mutations

    private func addTurn() {
        guard canAddTurn else { return }
        // Default to the previous turn's creature so authors can keep typing a back-and-forth.
        let defaultCreature = script.turns.last?.creatureId ?? creatures.first?.id ?? ""
        script.turns.append(DialogScriptTurn(creatureId: defaultCreature, text: ""))
    }

    private func removeTurn(id: UUID) {
        script.turns.removeAll { $0.id == id }
    }

    private func moveTurn(id: UUID, by offset: Int) {
        guard let index = script.turns.firstIndex(where: { $0.id == id }) else { return }
        let target = index + offset
        guard target >= 0, target < script.turns.count else { return }
        script.turns.swapAt(index, target)
    }

    // MARK: - Validation (debounced)

    private func scheduleValidation(for snapshot: DialogScript) {
        validateTask?.cancel()
        validateTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            if Task.isCancelled { return }
            await runValidation(for: snapshot)
        }
    }

    private func runValidation(for snapshot: DialogScript) async {
        await MainActor.run { isValidating = true }
        let result = await server.validateDialogScript(snapshot)
        if Task.isCancelled { return }
        await MainActor.run {
            isValidating = false
            switch result {
            case .success(let dto):
                validation = dto
            case .failure(let error):
                // Network/validation transport failures shouldn't nag with an alert on every
                // keystroke; log and leave the last good validation in place.
                logger.debug(
                    "validate request failed: \(ServerError.detailedMessage(from: error))")
            }
        }
    }

    // MARK: - Save / delete

    private func save() {
        if let problem = localLimitProblem {
            showError(title: "Cannot Save", message: problem)
            return
        }
        isSaving = true
        savingMessage = createNew ? "Creating dialog…" : "Saving dialog…"
        let toSave = script
        Task {
            let result =
                createNew
                ? await server.createDialogScript(toSave)
                : await server.updateDialogScript(toSave)
            await MainActor.run {
                isSaving = false
                switch result {
                case .success(let saved):
                    logger.info("saved dialog script \(saved.id)")
                    // Replace both copies with the server's canonical record so dirty detection
                    // and render-by-id work; this also picks up server-stamped timestamps.
                    original = saved
                    script = saved
                    createNew = false
                    CacheInvalidationProcessor.rebuildDialogScriptCache(deleteStaleEntries: true)
                    flashSavedBanner()
                case .failure(let error):
                    showError(
                        title: "Save Failed", message: ServerError.detailedMessage(from: error))
                }
            }
        }
    }

    private func deleteScript() {
        let id = original.id
        isSaving = true
        savingMessage = "Deleting dialog…"
        Task {
            let result = await server.deleteDialogScript(id: id)
            await MainActor.run {
                isSaving = false
                switch result {
                case .success(let message):
                    logger.info("dialog script deleted: \(message)")
                    CacheInvalidationProcessor.rebuildDialogScriptCache(deleteStaleEntries: true)
                    dismiss()
                case .failure(let error):
                    showError(
                        title: "Delete Failed", message: ServerError.detailedMessage(from: error))
                }
            }
        }
    }

    private func flashSavedBanner() {
        withAnimation { savedBanner = true }
        Task {
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run { withAnimation { savedBanner = false } }
        }
    }

    private func showError(title: String, message: String) {
        alertTitle = title
        alertMessage = message
        showErrorAlert = true
    }
}
