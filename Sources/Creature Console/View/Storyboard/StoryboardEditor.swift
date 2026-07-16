import Common
import Foundation
import OSLog
import SwiftData
import SwiftUI

/// Free-form editor for a `Storyboard`: drag/resize tiles on a relative-coordinate canvas and
/// program each tile's action via an inspector. Operates on a local `@State` copy (struct value
/// semantics, mirroring `DialogScriptEditor`); saves via the server CRUD.
struct StoryboardEditor: View {

    private let logger = Logger(
        subsystem: "io.opsnlops.CreatureConsole", category: "StoryboardEditor")

    @State private var createNew: Bool
    @State private var original: Storyboard
    @State private var board: Storyboard
    /// Highlighted/selected tile (shows the selection border + resize handle). Set by both tap and
    /// drag, on both platforms.
    @State private var selectedTileID: UUID? = nil
    /// Drives the iOS editor *sheet* — set only by an explicit tap, never by dragging, so moving a
    /// tile doesn't pop the inspector over the canvas. (macOS uses the side column instead.)
    @State private var editingTileID: UUID? = nil

    @State private var isSaving = false
    @State private var savingMessage = ""
    @State private var savedBanner = false
    @State private var showErrorAlert = false
    @State private var alertTitle = "Error"
    @State private var alertMessage = ""

    // Drag/resize anchors captured at gesture start (fractions).
    @State private var dragStart: [UUID: CGPoint] = [:]
    @State private var resizeStart: [UUID: CGSize] = [:]

    @Environment(\.dismiss) private var dismiss

    @Query(sort: \CreatureModel.name, order: .forward) private var creatures: [CreatureModel]
    @Query(sort: \AnimationMetadataModel.title, order: .forward)
    private var animations: [AnimationMetadataModel]
    @Query(sort: \PlaylistModel.name, order: .forward) private var playlists: [PlaylistModel]
    @Query(sort: \SoundModel.id, order: .forward) private var sounds: [SoundModel]
    @Query(sort: \DmxFixtureModel.name, order: .forward) private var fixtures: [DmxFixtureModel]
    @Query(sort: \DialogScriptModel.updatedAtMillis, order: .reverse)
    private var dialogs: [DialogScriptModel]

    private let server = CreatureServerClient.shared

    init(createNew: Bool) {
        let template = Storyboard.newEmpty()
        _createNew = State(initialValue: createNew)
        _original = State(initialValue: template)
        _board = State(initialValue: template)
    }

    init(existing: Storyboard) {
        _createNew = State(initialValue: false)
        _original = State(initialValue: existing)
        _board = State(initialValue: existing)
    }

    private var isDirty: Bool { board != original }

    /// First client-side validation problem (matches the server's caps), or `nil` if savable.
    private var localLimitProblem: String? {
        if board.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Give the storyboard a title."
        }
        if board.title.count > StoryboardLimits.maxTitle {
            return "Title is too long (max \(StoryboardLimits.maxTitle) characters)."
        }
        if board.notes.count > StoryboardLimits.maxNotes {
            return "Notes are too long (max \(StoryboardLimits.maxNotes) characters)."
        }
        if board.tiles.count > StoryboardLimits.maxTiles {
            return "Too many tiles (max \(StoryboardLimits.maxTiles))."
        }
        if board.tiles.contains(where: { $0.label.count > StoryboardLimits.maxTileLabel }) {
            return "A tile label is too long (max \(StoryboardLimits.maxTileLabel) characters)."
        }
        // A tile that would fail at perform time (empty animation/creature/… id) must not save —
        // mid-show is the worst moment to find out a button does nothing.
        for tile in board.tiles {
            if let problem = tile.action.configurationProblem {
                return "Tile “\(tile.label)” \(problem)."
            }
        }
        return nil
    }

    var body: some View {
        content
            .navigationTitle(
                createNew ? "New Storyboard" : (board.title.isEmpty ? "Storyboard" : board.title)
            )
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: save) {
                        Label("Save", systemImage: "square.and.arrow.down")
                    }
                    .disabled(isSaving || localLimitProblem != nil)
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button(action: addTile) {
                        Label("Add Tile", systemImage: "plus.square")
                    }
                    .disabled(board.tiles.count >= StoryboardLimits.maxTiles)
                }
                if !createNew {
                    ToolbarItem(placement: .secondaryAction) {
                        Button(role: .destructive, action: deleteBoard) {
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
            .overlay(alignment: .top) { banner }
    }

    @ViewBuilder
    private var content: some View {
        #if os(macOS)
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    detailsBar
                    canvas
                }
                Divider()
                inspectorColumn
                    .frame(width: 340)
            }
        #else
            VStack(spacing: 0) {
                detailsBar
                canvas
            }
            .sheet(
                isPresented: Binding(
                    get: { editingTileID != nil },
                    set: { if !$0 { editingTileID = nil } })
            ) {
                NavigationStack {
                    ScrollView { inspectorContent(for: editingTileID).padding() }
                        .navigationTitle("Tile")
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { editingTileID = nil }
                            }
                        }
                }
                .presentationDetents([.medium, .large])
            }
        #endif
    }

    // MARK: - Details bar

    private var detailsBar: some View {
        VStack(spacing: 6) {
            TextField("Storyboard title", text: $board.title)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
            TextField("Notes (optional)", text: $board.notes)
                .textFieldStyle(.roundedBorder)
                .font(.subheadline)
            HStack {
                if let problem = localLimitProblem {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Spacer()
                Text("\(board.tiles.count)/\(StoryboardLimits.maxTiles) tiles")
                    .font(.caption)
                    .foregroundStyle(
                        board.tiles.count >= StoryboardLimits.maxTiles ? .red : .secondary)
            }
        }
        .padding(12)
    }

    // MARK: - Canvas

    private var canvas: some View {
        // Establish the 16:10 frame on a flexible view first, then read geometry from an *overlay*
        // GeometryReader. `GeometryReader { … }.aspectRatio(.fit)` is unreliable — the reader reports
        // a size that doesn't match the visible box, so drag math (translation ÷ height) and the
        // edge clamp are computed against the wrong height (tiles top out at the middle and spill
        // past the bottom). This idiom guarantees `geo.size` *is* the visible canvas.
        Color.clear
            .aspectRatio(16.0 / 10.0, contentMode: .fit)
            .overlay {
                GeometryReader { geo in
                    let size = geo.size
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.black.opacity(0.85))
                            .onTapGesture { selectedTileID = nil }

                        StoryboardTileLayer(canvasSize: size) {
                            ForEach($board.tiles) { $tile in
                                tileView(tile: $tile, canvasSize: size)
                            }
                        }

                        if board.tiles.isEmpty {
                            Text("Tap “Add Tile” to place a button, then program what it does.")
                                .foregroundStyle(.white.opacity(0.6))
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .allowsHitTesting(false)
                        }
                    }
                    // A stable coordinate space for drag/resize translation. Without this, the
                    // gestures measure translation in the tile's *own* frame — which `.position`
                    // moves as the tile is dragged — so the motion partly cancels itself out and the
                    // tile can never reach the edges (it converges toward the middle).
                    .coordinateSpace(.named(StoryboardCanvas.coordinateSpace))
                }
            }
            .padding(12)
    }

    @ViewBuilder
    private func tileView(tile: Binding<StoryboardTile>, canvasSize: CGSize) -> some View {
        let t = tile.wrappedValue
        // Frame first, then gestures/overlay, then position — `storyboardTilePosition` expands the
        // tile to fill the parent, so gestures must attach to the tile-sized frame before it (else
        // the top-most tile's hit area would swallow the whole canvas). See `StoryboardCanvas`.
        StoryboardTileButton(tile: t, isSelected: t.id == selectedTileID)
            .storyboardTileFrame(t, in: canvasSize, minSide: 28)
            .overlay(alignment: .bottomTrailing) {
                if t.id == selectedTileID {
                    resizeHandle(tile: tile, canvasSize: canvasSize)
                }
            }
            .onTapGesture {
                selectedTileID = t.id
                // On iOS a tap opens the editor sheet; on macOS the side column already shows it.
                #if os(iOS)
                    editingTileID = t.id
                #endif
            }
            .gesture(moveGesture(tile: tile, canvasSize: canvasSize))
            .storyboardTilePosition(t, in: canvasSize)
    }

    private func resizeHandle(tile: Binding<StoryboardTile>, canvasSize: CGSize) -> some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.black)
            .padding(6)
            .background(.white, in: Circle())
            .offset(x: 6, y: 6)
            .gesture(
                DragGesture(
                    minimumDistance: 1, coordinateSpace: .named(StoryboardCanvas.coordinateSpace)
                )
                .onChanged { value in
                    let id = tile.wrappedValue.id
                    if resizeStart[id] == nil {
                        resizeStart[id] = CGSize(
                            width: tile.wrappedValue.width, height: tile.wrappedValue.height)
                    }
                    let start = resizeStart[id] ?? .zero
                    let nw = start.width + value.translation.width / canvasSize.width
                    let nh = start.height + value.translation.height / canvasSize.height
                    tile.wrappedValue.width = min(max(nw, 0.08), 1 - tile.wrappedValue.x)
                    tile.wrappedValue.height = min(max(nh, 0.08), 1 - tile.wrappedValue.y)
                }
                .onEnded { _ in resizeStart[tile.wrappedValue.id] = nil }
            )
    }

    private func moveGesture(tile: Binding<StoryboardTile>, canvasSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named(StoryboardCanvas.coordinateSpace))
            .onChanged { value in
                let id = tile.wrappedValue.id
                selectedTileID = id
                if dragStart[id] == nil {
                    dragStart[id] = CGPoint(x: tile.wrappedValue.x, y: tile.wrappedValue.y)
                }
                let start = dragStart[id] ?? .zero
                let nx = start.x + value.translation.width / canvasSize.width
                let ny = start.y + value.translation.height / canvasSize.height
                tile.wrappedValue.x = min(max(nx, 0), 1 - tile.wrappedValue.width)
                tile.wrappedValue.y = min(max(ny, 0), 1 - tile.wrappedValue.height)
            }
            .onEnded { _ in dragStart[tile.wrappedValue.id] = nil }
    }

    // MARK: - Inspector

    private var inspectorColumn: some View {
        ScrollView {
            inspectorContent(for: selectedTileID).padding()
        }
    }

    @ViewBuilder
    private func inspectorContent(for id: UUID?) -> some View {
        if let id, let binding = tileBinding(id) {
            StoryboardTileInspector(
                tile: binding,
                creatures: creatures, animations: animations, playlists: playlists,
                sounds: sounds, fixtures: fixtures, dialogs: dialogs,
                onDelete: { removeTile(id) })
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("No tile selected").font(.headline)
                Text("Drag a tile to move it; tap it to program what it does.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var banner: some View {
        if isSaving {
            Text(savingMessage)
                .font(.title3)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .glassEffect(.regular, in: .capsule)
                .padding(.top, 12)
        } else if savedBanner {
            Label("Saved", systemImage: "checkmark.circle.fill")
                .font(.title3)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .glassEffect(.regular.tint(.green.opacity(0.4)), in: .capsule)
                .padding(.top, 12)
        }
    }

    // MARK: - Tile mutations

    private func tileBinding(_ id: UUID) -> Binding<StoryboardTile>? {
        guard let index = board.tiles.firstIndex(where: { $0.id == id }) else { return nil }
        return $board.tiles[index]
    }

    private func addTile() {
        // Seed with the default action kind's symbol so a new tile reads as something specific
        // rather than a generic square. (The inspector keeps the symbol in sync as the type changes,
        // unless the author types a custom one.)
        let kind = ActionKind.playSound
        // Cascade placement so consecutive adds don't stack invisibly on one spot.
        let index = board.tiles.count
        let tile = StoryboardTile(
            x: 0.08 + Double(index % 3) * 0.30,
            y: 0.08 + Double((index / 3) % 3) * 0.28,
            width: 0.24, height: 0.20,
            label: "New", sfSymbol: kind.defaultSymbol, tintColorHex: "#0A84FF",
            action: kind.defaultAction(sounds: sounds, dialogs: dialogs))
        board.tiles.append(tile)
        selectedTileID = tile.id
        #if os(iOS)
            editingTileID = tile.id
        #endif
    }

    private func removeTile(_ id: UUID) {
        board.tiles.removeAll { $0.id == id }
        if selectedTileID == id { selectedTileID = nil }
        if editingTileID == id { editingTileID = nil }
    }

    // MARK: - Save / delete

    private func save() {
        if let problem = localLimitProblem {
            showError("Cannot Save", problem)
            return
        }
        isSaving = true
        savingMessage = createNew ? "Creating storyboard…" : "Saving storyboard…"
        let toSave = board
        Task {
            let result =
                createNew
                ? await server.createStoryboard(toSave)
                : await server.updateStoryboard(toSave)
            await MainActor.run {
                isSaving = false
                switch result {
                case .success(let saved):
                    original = saved
                    board = saved
                    createNew = false
                    CacheInvalidationProcessor.rebuildStoryboardCache(deleteStaleEntries: true)
                    flashSavedBanner()
                case .failure(let error):
                    showError("Save Failed", ServerError.detailedMessage(from: error))
                }
            }
        }
    }

    private func deleteBoard() {
        let id = original.id
        isSaving = true
        savingMessage = "Deleting storyboard…"
        Task {
            let result = await server.deleteStoryboard(id: id)
            await MainActor.run {
                isSaving = false
                switch result {
                case .success:
                    CacheInvalidationProcessor.rebuildStoryboardCache(deleteStaleEntries: true)
                    dismiss()
                case .failure(let error):
                    showError("Delete Failed", ServerError.detailedMessage(from: error))
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

    private func showError(_ title: String, _ message: String) {
        alertTitle = title
        alertMessage = message
        showErrorAlert = true
    }
}
