import SwiftUI
import WorldCore

/// How the panel splits the scenes. Kept out of the view, so it is no actor's and tests can
/// call it from anywhere.
enum HouseScenes {
    /// The scenes a bird is told, by name: offered by the house and not set aside.
    static func askable(_ scenes: [HouseScene]) -> [HouseScene] {
        scenes.filter { $0.offered && $0.askable }.sorted { $0.name < $1.name }
    }

    /// Everything else: set aside, or described but no longer offered by the house.
    static func setAside(_ scenes: [HouseScene]) -> [HouseScene] {
        scenes.filter { !($0.offered && $0.askable) }.sorted { $0.name < $1.name }
    }
}

/// The house's lighting scenes, as the birds are told them (#241): what each one is, and
/// whether a bird may ask for it. A bird reads these lines when April asks for the lights -
/// "make it cozy" once offered Sleepy Time, which only dims the outside lights.
struct HousePanel: View {
    let store: WorldStore
    @State private var scenes: [HouseScene] = []
    @State private var loading = false

    var body: some View {
        List {
            Section("Birds may ask for") {
                ForEach(HouseScenes.askable(scenes), id: \.name) { scene in
                    HouseSceneRow(scene: scene, save: save)
                }
            }
            let setAside = HouseScenes.setAside(scenes)
            if !setAside.isEmpty {
                Section("Set aside") {
                    ForEach(setAside, id: \.name) { scene in
                        HouseSceneRow(scene: scene, save: save)
                    }
                }
            }
        }
        .overlay {
            if scenes.isEmpty && !loading {
                ContentUnavailableView(
                    "No scenes yet", systemImage: "lightbulb.slash",
                    description: Text("The house announces its scenes when it connects."))
            } else if loading && scenes.isEmpty {
                ProgressView()
            }
        }
        .task { await load() }
        .toolbar {
            ToolbarItem {
                Button("Refresh", systemImage: "arrow.triangle.2.circlepath") {
                    Task { await load() }
                }
            }
        }
    }

    private func load() async {
        loading = true
        scenes = await store.houseScenes()
        loading = false
    }

    private func save(_ name: String, _ description: String, _ askable: Bool) {
        Task {
            guard
                let saved = await store.describeScene(
                    name, description: description, askable: askable)
            else { return }
            if let index = scenes.firstIndex(where: { $0.name == name }) {
                var updated = saved
                updated.offered = scenes[index].offered
                scenes[index] = updated
            }
        }
    }
}

private struct HouseSceneRow: View {
    let scene: HouseScene
    let save: (String, String, Bool) -> Void
    @State private var draft = ""
    @FocusState private var editing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(scene.name).font(.headline)
                if !scene.offered {
                    Text("no longer offered")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .glassEffect(.regular.tint(.orange.opacity(0.3)), in: .capsule)
                }
                Spacer()
                if let by = scene.updatedBy {
                    Text(by == "world:draft" ? "draft" : "described by \(by)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Toggle(
                    "Birds may ask",
                    isOn: Binding(
                        get: { scene.askable },
                        set: { save(scene.name, current, $0) })
                )
                .toggleStyle(.switch)
                .controlSize(.mini)
                .help("Off: the birds are never told this scene, and the World refuses it")
            }
            TextField("What does this scene do?", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .fixedSize(horizontal: false, vertical: true)
                .focused($editing)
                .onSubmit(commit)
                .onChange(of: editing) { _, focused in
                    if !focused { commit() }
                }
        }
        .padding(.vertical, 3)
        .onAppear { draft = scene.description }
        .onChange(of: scene.description) { _, new in
            if !editing { draft = new }
        }
    }

    private var current: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func commit() {
        guard current != scene.description else { return }
        save(scene.name, current, scene.askable)
    }
}
