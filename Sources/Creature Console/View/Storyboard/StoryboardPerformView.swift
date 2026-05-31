import Common
import OSLog
import SwiftData
import SwiftUI

#if canImport(UIKit)
    import UIKit
#endif

/// Full-screen, distraction-free performance surface. Tiles are laid out by their relative
/// coordinates and tapped to fire actions (with haptic + brief confirmation). Touch-only — the
/// joystick is reserved for live control. A deliberate long-press exits so a stray tap never ends
/// the show.
struct StoryboardPerformView: View {

    /// The storyboard to perform. Resolved fresh from the live `@Query` by the presenting table
    /// (`StoryboardTable.performDestination`) at launch, so it always reflects the latest save.
    let storyboard: Storyboard

    private let logger = Logger(
        subsystem: "io.opsnlops.CreatureConsole", category: "StoryboardPerformView")

    @Environment(\.dismiss) private var dismiss
    @Query private var fixtures: [DmxFixtureModel]

    @State private var runner = StoryboardActionRunner()
    @State private var liveCreatureId: CreatureIdentifier?
    @State private var flash: [UUID: Bool] = [:]
    @State private var flashError: [UUID: Bool] = [:]
    @State private var toast: String?
    @State private var pendingPrompt: PendingPrompt?
    @State private var fixtureSheet: FixtureSheetItem?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GeometryReader { geo in
                StoryboardTileLayer(canvasSize: geo.size) {
                    ForEach(storyboard.tiles) { tile in
                        tileButton(tile, canvasSize: geo.size)
                    }
                }
            }
            .padding(20)

            exitControl
            if let toast { toastBanner(toast) }
        }
        .statusBarHiddenIfAvailable()
        .task {
            runner.fixtureLookup = { id in
                fixtures.first(where: { $0.id == id })?.toDTO()
            }
            liveCreatureId = await CreatureManager.shared.currentStreamingCreature()
            for await _ in await AppState.shared.stateUpdates {
                liveCreatureId = await CreatureManager.shared.currentStreamingCreature()
            }
        }
        .sheet(item: $pendingPrompt) { prompt in
            AdHocSpeechPrompt(creatureName: prompt.creatureName) { text in
                pendingPrompt = nil
                Task { await fire(prompt.action, on: prompt.tileID, promptText: text) }
            } onCancel: {
                pendingPrompt = nil
            }
        }
        .sheet(item: $fixtureSheet) { item in
            if let fixture = fixtures.first(where: { $0.id == item.fixtureId })?.toDTO() {
                FixtureControlSheet(fixture: fixture)
            } else {
                Text("Fixture not found").padding()
            }
        }
    }

    private func tileButton(_ tile: StoryboardTile, canvasSize: CGSize) -> some View {
        Button {
            Task { await fire(tile.action, on: tile.id) }
        } label: {
            StoryboardTileButton(tile: tile, highlighted: isLive(tile))
                .overlay(flashOverlay(for: tile.id))
        }
        .buttonStyle(.plain)
        .storyboardTileFrame(tile, in: canvasSize, minSide: 36)
        .storyboardTilePosition(tile, in: canvasSize)
    }

    @ViewBuilder
    private func flashOverlay(for id: UUID) -> some View {
        if flash[id] == true {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(flashError[id] == true ? Color.red : Color.white, lineWidth: 5)
        }
    }

    private var exitControl: some View {
        VStack {
            HStack {
                exitButton
                Spacer()
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var exitButton: some View {
        let glyph =
            Image(systemName: "xmark")
            .font(.headline)
            .foregroundStyle(.white.opacity(0.5))
            .padding(12)
            .glassEffect(.regular.interactive(), in: .circle)
        #if os(macOS)
            // macOS: a normal click (and Escape) — long-press isn't a natural trackpad gesture.
            Button(action: dismiss.callAsFunction) { glyph }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .padding(16)
        #else
            // iOS: deliberate long-press so a stray tap during a show never ends it.
            glyph
                .padding(16)
                .contentShape(Rectangle())
                .onLongPressGesture(minimumDuration: 0.8) { dismiss() }
        #endif
    }

    private func toastBanner(_ message: String) -> some View {
        VStack {
            Spacer()
            Text(message)
                .font(.callout)
                .foregroundStyle(.white)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .glassEffect(.regular.tint(.red.opacity(0.6)), in: .capsule)
                .padding(.bottom, 40)
        }
        .transition(.opacity)
    }

    private func isLive(_ tile: StoryboardTile) -> Bool {
        if case .liveControl(let creatureId, _) = tile.action {
            return creatureId == liveCreatureId
        }
        return false
    }

    private func fire(_ action: StoryboardAction, on tileID: UUID, promptText: String? = nil) async
    {
        impact()
        let outcome = await runner.run(action, promptText: promptText)
        switch outcome {
        case .success:
            await showFlash(tileID, error: false)
            liveCreatureId = await CreatureManager.shared.currentStreamingCreature()
        case .failure(let message):
            await showFlash(tileID, error: true)
            showToast(message)
        case .needsPrompt(let creatureId):
            pendingPrompt = PendingPrompt(
                tileID: tileID, action: action,
                creatureName: creatureName(creatureId))
        case .presentFixtureSheet(let fixtureId):
            fixtureSheet = FixtureSheetItem(fixtureId: fixtureId)
        }
    }

    private func creatureName(_ id: CreatureIdentifier) -> String {
        // The perform view doesn't query creatures; fall back to the id (the prompt is brief).
        id
    }

    @MainActor
    private func showFlash(_ id: UUID, error: Bool) async {
        flash[id] = true
        flashError[id] = error
        try? await Task.sleep(for: .milliseconds(400))
        flash[id] = false
        flashError[id] = false
    }

    private func showToast(_ message: String) {
        withAnimation { toast = message }
        Task {
            try? await Task.sleep(for: .seconds(4))
            await MainActor.run { withAnimation { toast = nil } }
        }
    }

    private func impact() {
        #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
    }
}

private struct PendingPrompt: Identifiable {
    let id = UUID()
    let tileID: UUID
    let action: StoryboardAction
    let creatureName: String
}

private struct FixtureSheetItem: Identifiable {
    let id = UUID()
    let fixtureId: DmxFixtureIdentifier
}

/// A brief text prompt for ad-hoc speech tiles.
private struct AdHocSpeechPrompt: View {
    let creatureName: String
    let onSubmit: (String) -> Void
    let onCancel: () -> Void

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 8) {
                Text("What should \(creatureName) say?").font(.headline)
                TextEditor(text: $text)
                    .focused($focused)
                    .frame(minHeight: 140)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                Spacer()
            }
            .padding()
            .navigationTitle("Ad-Hoc Speech")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speak") { onSubmit(text) }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { focused = true }
        }
        #if os(macOS)
            .frame(minWidth: 420, minHeight: 240)
        #endif
    }
}

/// A live fixture control sheet (On / Off / Pattern / Color), reusing `FixtureControlService`.
private struct FixtureControlSheet: View {
    let fixture: DmxFixture

    @Environment(\.dismiss) private var dismiss
    @State private var selectedPattern: FixturePatternIdentifier = ""
    @State private var color: Color = .white
    @State private var status: String?

    private let server = CreatureServerClient.shared

    var body: some View {
        NavigationStack {
            Form {
                Section("On / Off") {
                    HStack {
                        Button {
                            run { await FixtureControlService.turnOn(fixture, server: server) }
                        } label: {
                            Label("On", systemImage: "lightbulb.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        Button(role: .destructive) {
                            run { await FixtureControlService.turnOff(fixture, server: server) }
                        } label: {
                            Label("Off", systemImage: "lightbulb.slash")
                        }
                    }
                }
                if !fixture.patterns.isEmpty {
                    Section("Pattern") {
                        Picker("Pattern", selection: $selectedPattern) {
                            Text("Select…").tag("")
                            ForEach(fixture.patterns) { pattern in
                                Text(pattern.name).tag(pattern.id)
                            }
                        }
                        Button("Trigger Pattern") {
                            let id = selectedPattern
                            run {
                                await FixtureControlService.trigger(
                                    patternId: id, on: fixture.id, server: server)
                            }
                        }
                        .disabled(selectedPattern.isEmpty)
                    }
                }
                Section("Color") {
                    ColorPicker("Color", selection: $color, supportsOpacity: false)
                    Button("Set Color") {
                        let chosen = color
                        run {
                            await FixtureControlService.setColor(
                                chosen, on: fixture, server: server)
                        }
                    }
                }
                if let status {
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(fixture.name)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
            .frame(minWidth: 420, minHeight: 380)
        #endif
    }

    private func run(_ operation: @escaping () async -> Result<DmxFixture, ServerError>) {
        Task {
            let result = await operation()
            await MainActor.run {
                if case .failure(let error) = result {
                    status = ServerError.detailedMessage(from: error)
                } else {
                    status = nil
                }
            }
        }
    }
}

extension View {
    /// Hide the status bar where the platform supports it (iOS); no-op on macOS.
    @ViewBuilder
    fileprivate func statusBarHiddenIfAvailable() -> some View {
        #if os(iOS)
            self.statusBarHidden(true)
        #else
            self
        #endif
    }
}
