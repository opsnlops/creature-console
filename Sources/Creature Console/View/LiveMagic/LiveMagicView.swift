import Common
import OSLog
import SwiftData
import SwiftUI

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

struct LiveMagicView: View {

    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel = LiveMagicViewModel()
    @Query(sort: \CreatureModel.name, order: .forward)
    private var creatures: [CreatureModel]

    private let logger = Logger(
        subsystem: "io.opsnlops.CreatureConsole", category: "LiveMagicView")

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                quickActionsCard

                if !viewModel.jobCards.isEmpty {
                    jobStatusSection
                }

                preparedCuesSection
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
        .background(Color.clear)
        .navigationTitle("Live Magic")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.presentPrompt(for: .instant)
                } label: {
                    Label("Instant Speech", systemImage: "bolt.fill")
                }
                .keyboardShortcut("n", modifiers: [.command])
            }
        }
        .sheet(isPresented: $viewModel.isPresentingPrompt) {
            LiveMagicPromptSheet(
                mode: viewModel.promptMode,
                creatures: creatures.map { $0.toDTO() },
                isSubmitting: viewModel.isSubmittingPrompt,
                onCancel: { viewModel.dismissPrompt() },
                onSubmit: { request in
                    Task {
                        await viewModel.submitPrompt(request)
                    }
                }
            )
        }
        .alert(item: $viewModel.alert) { descriptor in
            Alert(
                title: Text(descriptor.title),
                message: Text(descriptor.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .task {
            await importCreaturesIfNeeded()
        }
    }

    private var quickActionsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Live Magic Controls")
                .font(.title3.weight(.semibold))

            Text(
                "Craft jokes, riffs, and crowd work in the moment. These controls stay chunky so you can tap without hunting."
            )
            .font(.callout)
            .foregroundStyle(.secondary)

            LiveMagicActionButton(
                title: "Instant Speech",
                subtitle: "Generate dialog and perform immediately.",
                icon: "bolt.fill",
                tint: .orange
            ) {
                viewModel.presentPrompt(for: .instant)
            }

            LiveMagicActionButton(
                title: "Cue Speech",
                subtitle: "Precompute the bit and trigger it right on cue.",
                icon: "clock.arrow.circlepath",
                tint: .indigo
            ) {
                viewModel.presentPrompt(for: .cue)
            }
        }
        .padding()
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
    }

    private var jobStatusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("In Progress")
                .font(.headline)

            ForEach(viewModel.jobCards) { card in
                LiveMagicJobCardView(
                    card: card,
                    dismissAction: { viewModel.dismissJobCard(id: card.id) }
                )
            }
        }
        .padding()
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
    }

    private var preparedCuesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Prepared Cues")
                    .font(.headline)
                Spacer()
                if !viewModel.preparedCues.isEmpty {
                    Text("\(viewModel.preparedCues.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if viewModel.preparedCues.isEmpty {
                Text(
                    "Build a cue to see it here. Once the server finishes, you can fire it exactly when the crowd is ready."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 12) {
                    ForEach(viewModel.preparedCues) { cue in
                        PreparedCueRow(
                            cue: cue,
                            playAction: { resume in
                                Task {
                                    await viewModel.playCue(cue, resumePlaylist: resume)
                                }
                            },
                            discardAction: { viewModel.removeCue(cue) }
                        )
                    }
                }
            }
        }
        .padding()
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
    }

    private func importCreaturesIfNeeded() async {
        guard creatures.isEmpty else { return }
        do {
            let importer = CreatureImporter(modelContainer: modelContext.container)
            logger.debug("Fetching creature list for Live Magic view")
            let result = await CreatureServerClient.shared.getAllCreatures()
            switch result {
            case .success(let remoteCreatures):
                try await importer.upsertBatch(remoteCreatures)
            case .failure(let error):
                logger.error("Failed to import creatures: \(error.localizedDescription)")
            }
        } catch {
            logger.error("Error importing creatures: \(error.localizedDescription)")
        }
    }
}

private struct LiveMagicActionButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(tint.gradient)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct LiveMagicJobCardView: View {
    let card: LiveMagicViewModel.JobCard
    let dismissAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(card.context.creature.name)
                        .font(.headline)
                    Text(card.context.mode.title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Label(card.status.description, systemImage: card.status.symbolName)
                    .labelStyle(.titleAndIcon)
                    .font(.caption)
                    .foregroundStyle(card.status.tint)
            }

            Text(card.context.text)
                .font(.callout)
                .lineLimit(3)

            if let progress = card.progress {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
            } else if !card.isTerminal {
                ProgressView()
            }

            if let message = card.message, !message.isEmpty {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Dismiss") {
                    dismissAction()
                }
                .buttonStyle(.borderedProminent)
                .tint(.secondary)
            }
        }
        .padding()
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
    }
}

private struct PreparedCueRow: View {
    let cue: LiveMagicViewModel.PreparedCue
    let playAction: (Bool) -> Void
    let discardAction: () -> Void

    @State private var resumePlaylist: Bool

    init(
        cue: LiveMagicViewModel.PreparedCue,
        playAction: @escaping (Bool) -> Void,
        discardAction: @escaping () -> Void
    ) {
        self.cue = cue
        self.playAction = playAction
        self.discardAction = discardAction
        _resumePlaylist = State(initialValue: cue.defaultResumePlaylist)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(cue.creatureName)
                        .font(.headline)
                    Text("Ready")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(cue.soundFile)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(cue.script)
                .font(.body)
                .lineLimit(3)

            Toggle("Resume playlist after playback", isOn: $resumePlaylist)
                .toggleStyle(.switch)

            HStack {
                Button {
                    discardAction()
                } label: {
                    Label("Discard", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .tint(.red)

                Spacer()

                Button {
                    playAction(resumePlaylist)
                } label: {
                    Label("Play Cue", systemImage: "play.fill")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
    }
}

extension JobStatus {
    fileprivate var symbolName: String {
        switch self {
        case .queued:
            return "tray.and.arrow.down.fill"
        case .running:
            return "gear"
        case .completed:
            return "checkmark.circle.fill"
        case .failed:
            return "xmark.octagon.fill"
        default:
            return "questionmark"
        }
    }

    fileprivate var tint: Color {
        switch self {
        case .queued:
            return .gray
        case .running:
            return .blue
        case .completed:
            return .green
        case .failed:
            return .red
        default:
            return .secondary
        }
    }

    fileprivate var description: String {
        switch self {
        case .queued:
            return "Queued"
        case .running:
            return "Generating"
        case .completed:
            return "Ready"
        case .failed:
            return "Failed"
        default:
            return "Unknown"
        }
    }
}
