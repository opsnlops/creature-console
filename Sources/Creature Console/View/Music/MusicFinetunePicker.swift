import Common
import OSLog
import SwiftUI

/// The account's ElevenLabs Music finetunes, fetched once per launch and shared by every
/// composer on screen. Refreshable from the picker.
@MainActor
@Observable
final class MusicFinetuneStore {
    static let shared = MusicFinetuneStore()

    private let logger = Logger(
        subsystem: "io.opsnlops.CreatureConsole", category: "MusicFinetuneStore")

    private(set) var finetunes: [MusicFinetune] = []
    private(set) var isLoading = false
    private(set) var lastError: String?
    private var hasLoaded = false

    /// Loads the list the first time a picker appears; later calls are no-ops unless forced.
    func loadIfNeeded() async {
        guard !hasLoaded, !isLoading else { return }
        await refresh()
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        switch await CreatureServerClient.shared.listMusicFinetunes() {
        case .success(let list):
            // Ready ones first, then by name, so a picker reads like a menu of things that work.
            finetunes = list.items.sorted {
                if $0.isReady != $1.isReady { return $0.isReady }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            lastError = nil
            hasLoaded = true
        case .failure(let error):
            lastError = ServerError.detailedMessage(from: error)
            logger.warning("could not list music finetunes: \(self.lastError ?? "")")
        }
    }

    func finetune(withId id: String) -> MusicFinetune? {
        finetunes.first { $0.finetuneId == id }
    }
}

/// Finetune + strength, or none. Every ready finetune is offered: on prod all 45 are Music 2
/// finetunes and the server composes with them on Music 2.5 fine.
struct MusicFinetunePicker: View {
    @Binding var selection: MusicFinetuneSelection?

    @State private var store = MusicFinetuneStore.shared

    private var choices: [MusicFinetune] {
        store.finetunes.filter(\.isReady)
    }

    private var selectedId: Binding<String> {
        Binding(
            get: { selection?.finetuneId ?? "" },
            set: { newId in
                if newId.isEmpty {
                    selection = nil
                } else {
                    selection = MusicFinetuneSelection(
                        finetuneId: newId, strength: selection?.strength ?? 1.0)
                }
            })
    }

    private var strength: Binding<Double> {
        Binding(
            get: { selection?.strength ?? 1.0 },
            set: { newValue in
                guard let current = selection else { return }
                selection = MusicFinetuneSelection(
                    finetuneId: current.finetuneId, strength: newValue)
            })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Picker("Finetune", selection: selectedId) {
                    Text("None").tag("")
                    ForEach(choices) { finetune in
                        Text(finetuneTitle(finetune)).tag(finetune.finetuneId)
                    }
                    // Keep a selection visible even when it isn't in the filtered list (it came
                    // from a recipe, or the list hasn't loaded yet) so it can't silently vanish.
                    if let selection, !choices.contains(where: { $0.id == selection.finetuneId }) {
                        Text(
                            store.finetune(withId: selection.finetuneId)?.name
                                ?? selection.finetuneId
                        )
                        .tag(selection.finetuneId)
                    }
                }
                if store.isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Button {
                        Task { await store.refresh() }
                    } label: {
                        Label("Refresh finetunes", systemImage: "arrow.clockwise")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                    .help("Reload the finetune list from the server")
                }
            }
            if selection != nil {
                HStack {
                    Text("Strength")
                    Slider(
                        value: strength,
                        in: DialogLimits
                            .minMusicFinetuneStrength...DialogLimits
                            .maxMusicFinetuneStrength,
                        step: 0.1)
                    Text(strength.wrappedValue.formatted(.number.precision(.fractionLength(1))))
                        .font(.caption.monospacedDigit())
                        .frame(width: 32, alignment: .trailing)
                }
                .font(.caption)
            }
            if let error = store.lastError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .task { await store.loadIfNeeded() }
    }

    private func finetuneTitle(_ finetune: MusicFinetune) -> String {
        var title = finetune.name
        if let genre = finetune.primaryGenre, !genre.isEmpty {
            title += " · \(genre)"
        }
        return title
    }
}
