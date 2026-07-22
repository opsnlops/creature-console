import Common
import Foundation
import OSLog
import SwiftData
import SwiftUI

/// Top-level editor for a `DmxFixture`. Operates on a local mutable `@State` copy of the
/// fixture (created fresh when `createNew == true`, or copied from a server-fetched DTO
/// otherwise). Saves happen via the server REST API; universe assignment is a separate
/// endpoint with its own apply button (intentional — universe is persisted independently
/// from the rest of the fixture config).
struct FixtureEditor: View {

    private let logger = Logger(
        subsystem: "io.opsnlops.CreatureConsole", category: "FixtureEditor")

    /// `true` until the first successful save in create-new flow, then flipped to
    /// `false` so the universe-apply control, manual pattern fires, and the live
    /// control panel all light up without forcing the user back to the fixture table
    /// to re-open the freshly created record.
    @State private var createNew: Bool
    /// The fixture as it exists on the server *now* (right after the most recent
    /// save / universe apply / clear). Used to show "currently on server: X" hints
    /// and to know whether the universe action is creating new state vs reapplying
    /// the same value.
    @State private var original: Common.DmxFixture

    @State private var fixture: Common.DmxFixture
    @State private var universeText: String

    @State private var errorAlert: ErrorAlert?

    /// Informational (non-error) alerts: validation results, "Created", universe changes.
    @State private var infoAlert: ErrorAlert?

    @State private var isSaving = false
    @State private var savingMessage = ""

    /// Local "live is in effect until" deadline supplied by `LiveControlPanel`. While
    /// non-nil and in the future, the pattern fire buttons disable themselves (the
    /// server would refuse them anyway — `setLive` cancels active patterns and refuses
    /// new ones until the deadline expires).
    @State private var liveActiveUntil: Date? = nil

    @Environment(\.dismiss) private var dismiss

    let server = CreatureServerClient.shared

    /// Create-new initializer. Generates a fresh UUID and a one-channel scaffold so the
    /// fixture is immediately valid.
    init(createNew: Bool) {
        let template = Common.DmxFixture(
            id: UUID().uuidString.lowercased(),
            name: "New Fixture",
            type: .light,
            channelOffset: 0,
            assignedUniverse: nil,
            channels: [FixtureChannel(offset: 0, name: "channel1", kind: "generic")],
            patterns: [],
            bindings: []
        )
        _createNew = State(initialValue: createNew)
        _original = State(initialValue: template)
        _fixture = State(initialValue: template)
        _universeText = State(initialValue: "")
    }

    /// Edit-existing initializer. The caller passes the current DTO (e.g. from
    /// `DmxFixtureModel.toDTO()`). `DmxFixture` is a struct, so `@State` gets a fresh
    /// value-type copy automatically.
    init(existing: Common.DmxFixture) {
        _createNew = State(initialValue: false)
        _original = State(initialValue: existing)
        _fixture = State(initialValue: existing)
        _universeText = State(
            initialValue: existing.assignedUniverse.map { String($0) } ?? "")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                identitySection
                wiringSection
                universeSection
                ChannelListEditor(fixture: $fixture)
                if !createNew {
                    LiveControlPanel(
                        fixture: fixture,
                        onLiveActiveUntil: { deadline in
                            liveActiveUntil = deadline
                        }
                    )
                }
                PatternListEditor(
                    fixture: $fixture,
                    server: server,
                    liveActive: isLiveActive,
                    onTriggerError: showError
                )
                BindingListEditor(fixture: $fixture)
                Spacer(minLength: 40)
            }
            .padding()
        }
        .navigationTitle(createNew ? "New DMX Fixture" : fixture.name)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .secondaryAction) {
                Button(action: validate) {
                    Label("Validate", systemImage: "checkmark.seal")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button(action: save) {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .disabled(isSaving)
            }
            if !createNew {
                ToolbarItem(placement: .secondaryAction) {
                    Button(role: .destructive, action: deleteFixture) {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .errorAlert($errorAlert)
        .errorAlert($infoAlert)
        .overlay(alignment: .top) {
            if isSaving {
                Text(savingMessage)
                    .font(.title3)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .glassEffect(.regular, in: .capsule)
                    .padding(.top, 12)
                    .transition(.opacity)
            }
        }
    }

    // MARK: - Sections

    private var identitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Identity").font(.headline)
            HStack {
                Text("Name").frame(width: 100, alignment: .leading)
                TextField("Fixture Name", text: $fixture.name)
                    .textFieldStyle(.roundedBorder)
            }
            HStack {
                Text("Type").frame(width: 100, alignment: .leading)
                Picker("Type", selection: $fixture.type) {
                    ForEach(FixtureType.allCases, id: \.self) { type in
                        Text(displayName(for: type)).tag(type)
                    }
                }
                .labelsHidden()
            }
            HStack(alignment: .firstTextBaseline) {
                Text("ID").frame(width: 100, alignment: .leading)
                Text(fixture.id)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Spacer()
            }
        }
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }

    private var wiringSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("DMX Wiring").font(.headline)
            HStack {
                Text("Channel Offset").frame(width: 130, alignment: .leading)
                TextField(
                    "Offset (0–511)",
                    value: Binding<Int>(
                        get: { Int(fixture.channelOffset) },
                        set: { newValue in
                            fixture.channelOffset = UInt16(clamping: max(0, min(511, newValue)))
                        }
                    ),
                    format: .number
                )
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 120)

                Spacer()

                if let overflow = wiringOverflowMessage {
                    Label(overflow, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
            }

            Text(
                "Channel Offset is the starting DMX address within the universe. The fixture occupies channels \(fixture.channelOffset) through \(absoluteLastChannel) inclusive."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }

    private var universeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Universe Assignment").font(.headline)
                Spacer()
                if let server = original.assignedUniverse {
                    Text("Currently on server: \(server)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Currently on server: unassigned")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                TextField("Universe (1–63999), blank = unassigned", text: $universeText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 240)

                Button("Apply Universe") {
                    applyUniverse()
                }
                .disabled(createNew || isSaving)

                Button(role: .destructive, action: clearUniverse) {
                    Text("Clear")
                }
                .disabled(createNew || isSaving || original.assignedUniverse == nil)
            }

            Text(
                "Universe is persisted independently from the rest of the fixture config — Apply hits a dedicated endpoint so a universe change saves without touching channels, patterns, or bindings. Create the fixture first (Save), then assign a universe."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }

    // MARK: - Derived

    private var absoluteLastChannel: Int {
        let maxOffset = fixture.channels.map { Int($0.offset) }.max() ?? 0
        return Int(fixture.channelOffset) + maxOffset
    }

    private var wiringOverflowMessage: String? {
        guard absoluteLastChannel > 511 else { return nil }
        return "Overflows universe (\(absoluteLastChannel) > 511)"
    }

    private var isLiveActive: Bool {
        guard let deadline = liveActiveUntil else { return false }
        return deadline > Date()
    }

    private func displayName(for type: FixtureType) -> String {
        switch type {
        case .light: return "Light"
        case .smokeMachine: return "Smoke Machine"
        case .fogger: return "Fogger"
        case .generic: return "Generic"
        }
    }

    // MARK: - Actions

    private func validate() {
        guard let rawJson = encodeFixtureAsJsonString() else {
            showError(title: "Validation Error", message: "Unable to encode the fixture as JSON.")
            return
        }
        isSaving = true
        savingMessage = "Validating with server…"
        Task {
            let result = await server.validateFixture(rawJson: rawJson)
            isSaving = false
            switch result {
            case .success(let payload):
                var lines: [String] = []
                if payload.valid {
                    lines.append("Fixture is valid.")
                } else {
                    lines.append("Fixture is INVALID.")
                }
                if !payload.missingCreatureIds.isEmpty {
                    lines.append(
                        "Warning — bindings reference missing creature IDs:\n"
                            + payload.missingCreatureIds.map { "  • \($0)" }
                            .joined(separator: "\n"))
                }
                if !payload.errorMessages.isEmpty {
                    lines.append(
                        "Errors:\n"
                            + payload.errorMessages.map { "  • \($0)" }.joined(separator: "\n"))
                }
                infoAlert = ErrorAlert(
                    title: payload.valid ? "Valid" : "Invalid",
                    message: lines.joined(separator: "\n\n"))
            case .failure(let error):
                showError(
                    title: "Validation Failed",
                    message: ServerError.detailedMessage(from: error))
            }
        }
    }

    private func save() {
        // Local sanity check first — the server enforces this too, but doing it
        // client-side gives faster feedback.
        if let overflow = wiringOverflowMessage {
            showError(title: "Cannot Save", message: overflow)
            return
        }
        if fixture.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            showError(title: "Cannot Save", message: "Fixture name cannot be empty.")
            return
        }

        isSaving = true
        savingMessage = createNew ? "Creating fixture…" : "Saving fixture…"
        Task {
            let result = await server.upsertFixture(fixture)
            isSaving = false
            switch result {
            case .success(let saved):
                logger.info("upserted fixture \(saved.id)")
                // Trigger a cache refresh; the websocket invalidation will arrive
                // shortly after but the optimistic refresh helps the table update
                // immediately for the user.
                CacheInvalidationProcessor.rebuild(.fixture, deleteStaleEntries: true)
                original = saved
                if createNew {
                    // Flip into edit-existing mode in-place so the user can keep
                    // working — assign a universe, fire patterns to test, open the
                    // live control panel — without bouncing back through the
                    // fixtures table to re-open this same record.
                    createNew = false
                    infoAlert = ErrorAlert(
                        title: "Created",
                        message:
                            "Fixture '\(saved.name)' was created on the server. Assign a universe next so you can fire patterns and use live control."
                    )
                } else {
                    // Pop back to the table on update; the editor is no longer the
                    // source of truth.
                    dismiss()
                }
            case .failure(let error):
                showError(
                    title: "Save Failed",
                    message: ServerError.detailedMessage(from: error))
            }
        }
    }

    private func applyUniverse() {
        let trimmed = universeText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            clearUniverse()
            return
        }
        guard let value = UInt32(trimmed), (1...63999).contains(value) else {
            showError(
                title: "Invalid Universe",
                message: "Enter a value between 1 and 63999 (E1.31 valid range).")
            return
        }

        isSaving = true
        savingMessage = "Assigning universe \(value)…"
        Task {
            let result = await server.setFixtureUniverse(id: fixture.id, universe: value)
            isSaving = false
            switch result {
            case .success(let updated):
                logger.info("universe assigned to \(value) on \(updated.id)")
                fixture.assignedUniverse = updated.assignedUniverse
                original = updated
                CacheInvalidationProcessor.rebuild(.fixture, deleteStaleEntries: true)
                infoAlert = ErrorAlert(
                    title: "Universe Assigned",
                    message: "Fixture '\(updated.name)' is now assigned to universe \(value).")
            case .failure(let error):
                showError(
                    title: "Universe Assignment Failed",
                    message: ServerError.detailedMessage(from: error))
            }
        }
    }

    private func clearUniverse() {
        isSaving = true
        savingMessage = "Clearing universe…"
        Task {
            let result = await server.clearFixtureUniverse(id: fixture.id)
            isSaving = false
            switch result {
            case .success(let updated):
                logger.info("universe cleared on \(updated.id)")
                fixture.assignedUniverse = updated.assignedUniverse  // server says nil
                universeText = ""
                original = updated
                CacheInvalidationProcessor.rebuild(.fixture, deleteStaleEntries: true)
                infoAlert = ErrorAlert(
                    title: "Universe Cleared",
                    message: "Fixture '\(updated.name)' is no longer driving DMX.")
            case .failure(let error):
                showError(
                    title: "Failed to Clear Universe",
                    message: ServerError.detailedMessage(from: error))
            }
        }
    }

    private func deleteFixture() {
        let id = fixture.id
        isSaving = true
        savingMessage = "Deleting fixture…"
        Task {
            let result = await server.deleteFixture(id: id)
            isSaving = false
            switch result {
            case .success(let message):
                logger.info("fixture deleted: \(message)")
                CacheInvalidationProcessor.rebuild(.fixture, deleteStaleEntries: true)
                dismiss()
            case .failure(let error):
                showError(
                    title: "Delete Failed",
                    message: ServerError.detailedMessage(from: error))
            }
        }
    }

    private func showError(title: String, message: String) {
        errorAlert = ErrorAlert(title: title, message: message)
    }

    private func encodeFixtureAsJsonString() -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(fixture) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
