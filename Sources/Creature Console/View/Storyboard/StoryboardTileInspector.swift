import Common
import SwiftData
import SwiftUI

/// Programs a single storyboard tile: appearance (label / SF symbol / color) and its action
/// (type picker + per-type parameters, backed by the cached creatures / animations / playlists /
/// sounds / fixtures / dialogs).
struct StoryboardTileInspector: View {

    @Binding var tile: StoryboardTile

    let creatures: [CreatureModel]
    let animations: [AnimationMetadataModel]
    let playlists: [PlaylistModel]
    let sounds: [SoundModel]
    let fixtures: [DmxFixtureModel]
    let dialogs: [DialogScriptModel]
    let onDelete: () -> Void

    var body: some View {
        GlassEffectContainer(spacing: 16) {
            VStack(alignment: .leading, spacing: 16) {
                appearanceSection
                actionSection
                Button(role: .destructive, action: onDelete) {
                    Label("Delete Tile", systemImage: "trash")
                }
                .buttonStyle(.glass)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Appearance").font(.headline)
            LabeledContent("Label") {
                TextField("Label", text: $tile.label).textFieldStyle(.roundedBorder)
            }
            LabeledContent("SF Symbol") {
                TextField("e.g. hand.wave.fill", text: $tile.sfSymbol)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled(true)
                    #if os(iOS)
                        // SF Symbol names are lowercase & dotted — don't let iOS capitalize/correct.
                        .textInputAutocapitalization(.never)
                    #endif
            }
            ColorPicker(
                "Tint",
                selection: Binding(
                    get: { Color(storyboardHex: tile.tintColorHex) },
                    set: { tile.tintColorHex = $0.storyboardHexString() }),
                supportsOpacity: false)
            HStack {
                Spacer()
                StoryboardTileButton(tile: tile).frame(width: 120, height: 84)
                Spacer()
            }
        }
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }

    // MARK: - Action

    private var actionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Action").font(.headline)
            Picker("Type", selection: kindBinding) {
                ForEach(ActionKind.allCases) { kind in
                    Text(kind.label).tag(kind)
                }
            }
            actionParams
        }
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }

    private var kindBinding: Binding<ActionKind> {
        Binding(
            get: { ActionKind(from: tile.action) },
            set: { newKind in
                tile.action = newKind.defaultAction(sounds: sounds, dialogs: dialogs)
                // Track the type's default symbol unless the author has set a custom one. A symbol
                // that's empty, generic, or any kind's default counts as "not customized".
                let current = tile.sfSymbol.trimmingCharacters(in: .whitespaces)
                if current.isEmpty || ActionKind.defaultSymbols.contains(current) {
                    tile.sfSymbol = newKind.defaultSymbol
                }
            })
    }

    @ViewBuilder
    private var actionParams: some View {
        switch ActionKind(from: tile.action) {
        case .playAnimation:
            idPicker(
                "Animation", selection: animationIdBinding,
                options: animations.map { ($0.id, $0.title) })
            Toggle("Interrupt current", isOn: interruptBinding)
            Toggle("Resume playlist after", isOn: resumeBinding)
            universeField
        case .adHocSpeech:
            idPicker(
                "Creature", selection: creatureIdBinding,
                options: creatures.map { ($0.id, $0.name) })
            Toggle("Resume playlist after", isOn: resumeBinding)
            Text("Tapping this tile pops a text box, then speaks it.")
                .font(.caption).foregroundStyle(.secondary)
        case .liveControl:
            idPicker(
                "Creature", selection: creatureIdBinding,
                options: creatures.map { ($0.id, $0.name) })
            universeField
            Text("Toggles live control — turns green while this creature is being driven.")
                .font(.caption).foregroundStyle(.secondary)
        case .startPlaylist:
            idPicker(
                "Playlist", selection: playlistIdBinding,
                options: playlists.map { ($0.id, $0.name) })
            universeField
        case .stopPlaylist:
            universeField
        case .playSound:
            idPicker(
                "Sound", selection: soundFileBinding, options: sounds.map { ($0.id, $0.id) })
        case .renderDialog:
            idPicker(
                "Dialog", selection: dialogIdBinding,
                options: dialogs.map { ($0.id.uuidString.lowercased(), $0.title) })
        case .fixtureOn, .fixtureOff, .fixtureDetails:
            idPicker(
                "Fixture", selection: fixtureIdBinding,
                options: fixtures.map { ($0.id, $0.name) })
        case .fixturePattern:
            idPicker(
                "Fixture", selection: fixtureIdBinding,
                options: fixtures.map { ($0.id, $0.name) })
            idPicker("Pattern", selection: patternIdBinding, options: patternOptions)
        case .unknown:
            Text(
                "This tile uses an action this version of the app doesn't recognize. Update the app, or pick a different action."
            )
            .font(.caption).foregroundStyle(.orange)
        }
    }

    private var patternOptions: [(String, String)] {
        guard case .fixturePattern(let fixtureId, _, _) = tile.action,
            let fixture = fixtures.first(where: { $0.id == fixtureId })
        else { return [] }
        return fixture.toDTO().patterns.map { ($0.id, $0.name) }
    }

    // MARK: - Generic id picker

    @ViewBuilder
    private func idPicker(
        _ title: String, selection: Binding<String>, options: [(id: String, name: String)]
    ) -> some View {
        Picker(title, selection: selection) {
            Text("Select…").tag("")
            ForEach(options, id: \.id) { option in
                Text(option.name.isEmpty ? option.id : option.name).tag(option.id)
            }
            if !selection.wrappedValue.isEmpty,
                !options.contains(where: { $0.id == selection.wrappedValue })
            {
                Text("Unknown (\(selection.wrappedValue.prefix(8)))").tag(selection.wrappedValue)
            }
        }
    }

    private var universeField: some View {
        LabeledContent("Universe") {
            TextField("active", text: universeBinding)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 120)
        }
    }

    // MARK: - Param bindings (read current action, rebuild on change)

    private var animationIdBinding: Binding<String> {
        Binding(
            get: {
                if case .playAnimation(let id, _, _, _) = tile.action { return id }
                return ""
            },
            set: { newValue in
                if case .playAnimation(_, let u, let i, let r) = tile.action {
                    tile.action = .playAnimation(
                        animationId: newValue, universe: u, interrupt: i, resumePlaylist: r)
                }
            })
    }

    private var interruptBinding: Binding<Bool> {
        Binding(
            get: {
                if case .playAnimation(_, _, let i, _) = tile.action { return i }
                return false
            },
            set: { newValue in
                if case .playAnimation(let a, let u, _, let r) = tile.action {
                    tile.action = .playAnimation(
                        animationId: a, universe: u, interrupt: newValue, resumePlaylist: r)
                }
            })
    }

    private var resumeBinding: Binding<Bool> {
        Binding(
            get: {
                switch tile.action {
                case .playAnimation(_, _, _, let r): return r
                case .adHocSpeech(_, let r): return r
                default: return true
                }
            },
            set: { newValue in
                switch tile.action {
                case .playAnimation(let a, let u, let i, _):
                    tile.action = .playAnimation(
                        animationId: a, universe: u, interrupt: i, resumePlaylist: newValue)
                case .adHocSpeech(let c, _):
                    tile.action = .adHocSpeech(creatureId: c, resumePlaylist: newValue)
                default: break
                }
            })
    }

    private var creatureIdBinding: Binding<String> {
        Binding(
            get: {
                switch tile.action {
                case .adHocSpeech(let c, _): return c
                case .liveControl(let c, _): return c
                default: return ""
                }
            },
            set: { newValue in
                switch tile.action {
                case .adHocSpeech(_, let r):
                    tile.action = .adHocSpeech(creatureId: newValue, resumePlaylist: r)
                case .liveControl(_, let u):
                    tile.action = .liveControl(creatureId: newValue, universe: u)
                default: break
                }
            })
    }

    private var playlistIdBinding: Binding<String> {
        Binding(
            get: { if case .startPlaylist(let p, _) = tile.action { return p } else { return "" } },
            set: { newValue in
                if case .startPlaylist(_, let u) = tile.action {
                    tile.action = .startPlaylist(playlistId: newValue, universe: u)
                }
            })
    }

    private var soundFileBinding: Binding<String> {
        Binding(
            get: { if case .playSound(let f) = tile.action { return f } else { return "" } },
            set: { tile.action = .playSound(fileName: $0) })
    }

    private var dialogIdBinding: Binding<String> {
        Binding(
            get: {
                if case .renderDialog(let id) = tile.action {
                    return id.uuidString.lowercased()
                }
                return ""
            },
            set: { tile.action = .renderDialog(scriptId: UUID(uuidString: $0) ?? UUID()) })
    }

    private var fixtureIdBinding: Binding<String> {
        Binding(
            get: {
                switch tile.action {
                case .fixtureOn(let f), .fixtureOff(let f), .fixtureDetails(let f): return f
                case .fixturePattern(let f, _, _): return f
                default: return ""
                }
            },
            set: { newValue in
                switch tile.action {
                case .fixtureOn: tile.action = .fixtureOn(fixtureId: newValue)
                case .fixtureOff: tile.action = .fixtureOff(fixtureId: newValue)
                case .fixtureDetails: tile.action = .fixtureDetails(fixtureId: newValue)
                case .fixturePattern(_, let p, let s):
                    tile.action = .fixturePattern(
                        fixtureId: newValue, patternId: p, stopAfterMs: s)
                default: break
                }
            })
    }

    private var patternIdBinding: Binding<String> {
        Binding(
            get: {
                if case .fixturePattern(_, let p, _) = tile.action { return p } else { return "" }
            },
            set: { newValue in
                if case .fixturePattern(let f, _, let s) = tile.action {
                    tile.action = .fixturePattern(fixtureId: f, patternId: newValue, stopAfterMs: s)
                }
            })
    }

    private var universeBinding: Binding<String> {
        Binding(
            get: {
                switch tile.action {
                case .playAnimation(_, let u, _, _), .liveControl(_, let u),
                    .startPlaylist(_, let u), .stopPlaylist(let u):
                    return u.map(String.init) ?? ""
                default: return ""
                }
            },
            set: { newValue in
                let u = Int(newValue)
                switch tile.action {
                case .playAnimation(let a, _, let i, let r):
                    tile.action = .playAnimation(
                        animationId: a, universe: u, interrupt: i, resumePlaylist: r)
                case .liveControl(let c, _):
                    tile.action = .liveControl(creatureId: c, universe: u)
                case .startPlaylist(let p, _):
                    tile.action = .startPlaylist(playlistId: p, universe: u)
                case .stopPlaylist:
                    tile.action = .stopPlaylist(universe: u)
                default: break
                }
            })
    }
}

/// The selectable action types in the inspector (maps onto `StoryboardAction`).
enum ActionKind: String, CaseIterable, Identifiable {
    case playAnimation, adHocSpeech, liveControl, startPlaylist, stopPlaylist
    case playSound, renderDialog, fixtureOn, fixtureOff, fixturePattern, fixtureDetails
    case unknown

    var id: String { rawValue }

    var label: String {
        switch self {
        case .playAnimation: return "Play Animation"
        case .adHocSpeech: return "Ad-Hoc Speech"
        case .liveControl: return "Live Control"
        case .startPlaylist: return "Start Playlist"
        case .stopPlaylist: return "Stop Playlist"
        case .playSound: return "Play Sound"
        case .renderDialog: return "Render Dialog"
        case .fixtureOn: return "Fixture On"
        case .fixtureOff: return "Fixture Off"
        case .fixturePattern: return "Fixture Pattern"
        case .fixtureDetails: return "Fixture Details…"
        case .unknown: return "Unknown"
        }
    }

    /// The kinds offered in the picker (everything except `.unknown`).
    static var allCases: [ActionKind] {
        [
            .playAnimation, .adHocSpeech, .liveControl, .startPlaylist, .stopPlaylist,
            .playSound, .renderDialog, .fixtureOn, .fixtureOff, .fixturePattern, .fixtureDetails,
        ]
    }

    init(from action: StoryboardAction) {
        switch action {
        case .playAnimation: self = .playAnimation
        case .adHocSpeech: self = .adHocSpeech
        case .liveControl: self = .liveControl
        case .startPlaylist: self = .startPlaylist
        case .stopPlaylist: self = .stopPlaylist
        case .playSound: self = .playSound
        case .renderDialog: self = .renderDialog
        case .fixtureOn: self = .fixtureOn
        case .fixtureOff: self = .fixtureOff
        case .fixturePattern: self = .fixturePattern
        case .fixtureDetails: self = .fixtureDetails
        case .unknown: self = .unknown
        }
    }

    /// A sensible default SF Symbol for this kind, so a freshly-typed tile reads at a glance without
    /// the author having to know symbol names. Adopted automatically when switching types unless the
    /// author has typed a custom symbol (see `StoryboardTileInspector.kindBinding`).
    var defaultSymbol: String {
        switch self {
        case .playAnimation: return "play.fill"
        case .adHocSpeech: return "text.bubble.fill"
        case .liveControl: return "gamecontroller.fill"
        case .startPlaylist: return "play.square.stack.fill"
        case .stopPlaylist: return "stop.fill"
        case .playSound: return "speaker.wave.2.fill"
        case .renderDialog: return "bubble.left.and.bubble.right.fill"
        case .fixtureOn: return "lightbulb.fill"
        case .fixtureOff: return "lightbulb.slash.fill"
        case .fixturePattern: return "wand.and.rays"
        case .fixtureDetails: return "slider.horizontal.3"
        case .unknown: return "questionmark.square.dashed"
        }
    }

    /// The set of symbols any kind hands out as its default. A tile whose symbol is one of these (or
    /// empty/generic) is considered "not customized", so switching its type may re-default the symbol.
    static let defaultSymbols: Set<String> = Set(
        allCases.map(\.defaultSymbol) + ["square.fill", "square"])

    /// A sensible default action when the user switches a tile to this kind.
    func defaultAction(sounds: [SoundModel], dialogs: [DialogScriptModel]) -> StoryboardAction {
        switch self {
        case .playAnimation:
            return .playAnimation(
                animationId: "", universe: nil, interrupt: false, resumePlaylist: true)
        case .adHocSpeech: return .adHocSpeech(creatureId: "", resumePlaylist: true)
        case .liveControl: return .liveControl(creatureId: "", universe: nil)
        case .startPlaylist: return .startPlaylist(playlistId: "", universe: nil)
        case .stopPlaylist: return .stopPlaylist(universe: nil)
        case .playSound: return .playSound(fileName: sounds.first?.id ?? "")
        case .renderDialog: return .renderDialog(scriptId: dialogs.first?.id ?? UUID())
        case .fixtureOn: return .fixtureOn(fixtureId: "")
        case .fixtureOff: return .fixtureOff(fixtureId: "")
        case .fixturePattern:
            return .fixturePattern(fixtureId: "", patternId: "", stopAfterMs: nil)
        case .fixtureDetails: return .fixtureDetails(fixtureId: "")
        case .unknown: return .unknown(type: "", raw: [:])
        }
    }
}
