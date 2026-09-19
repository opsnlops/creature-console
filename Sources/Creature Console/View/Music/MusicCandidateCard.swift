import Common
import SwiftUI

/// One generated take: how it was made, and everything that can be done with it next —
/// listen, accept, or use it as the starting point for the next take.
struct MusicCandidateCard: View {
    let candidate: DialogMusicCandidate
    let isCurrent: Bool
    let isAccepted: Bool
    let hasAcceptedMusic: Bool
    let canPromote: Bool
    let isAuditioning: Bool

    let onAudition: () -> Void
    let onPromote: () -> Void
    let onEditPlan: (MusicReferenceTake, DialogMusicRecipe) -> Void
    let onKeepOpening: (MusicReferenceTake) -> Void
    let onSoundLike: (MusicReferenceTake) -> Void

    @State private var showsPlan = false

    private var recipe: DialogMusicRecipe? { candidate.result.recipe }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(candidate.label).font(.subheadline.bold())
                Text(headline)
                    .font(.subheadline)
                    .lineLimit(2)
                Spacer()
                Text(TimeHelper.formatDuration(candidate.result.durationSeconds))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Text(
                "Requested \(TimeHelper.formatDuration(Double(candidate.result.requestedMusicLengthMilliseconds) / 1_000)) • final show \(TimeHelper.formatDuration(candidate.result.finalShowDurationSeconds))"
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            if let recipe {
                Text(recipeLine(recipe))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let plan = recipe.compositionPlan {
                    DisclosureGroup(isExpanded: $showsPlan) {
                        MusicPlanSummary(plan: plan, reference: candidate.reference)
                            .padding(.top, 4)
                    } label: {
                        Text("Plan the server used • \(plan.chunks.count) section(s)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if candidate.isExpired {
                Label(
                    "This temporary candidate expired. Generate it again.",
                    systemImage: "clock.badge.exclamationmark"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            } else if !isCurrent {
                Label(
                    "Made for a different voice take than the accepted one — its timing won't match. Generate a new candidate.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }

            HStack {
                Button("Play with Dialog", action: onAudition)
                    .disabled(candidate.isExpired || !isCurrent || isAuditioning)
                if isAccepted {
                    Label("Accepted for Final Render", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Button(hasAcceptedMusic ? "Replace Accepted Music" : "Accept for Final Render")
                    {
                        onPromote()
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(candidate.isExpired || !isCurrent || !canPromote)
                }
                Spacer()
                nextTakeMenu
            }
        }
        .padding(12)
        .panelCard(cornerRadius: 10, tint: isAccepted ? .green : nil)
    }

    private var headline: String {
        if let recipe, let title = recipe.songTitle { return title }
        if !candidate.result.prompt.isEmpty { return candidate.result.prompt }
        return "Composed from a plan"
    }

    private func recipeLine(_ recipe: DialogMusicRecipe) -> String {
        var parts: [String] = [recipe.model?.displayName ?? recipe.modelId]
        if let mode = recipe.generationMode { parts.append(mode.rawValue.capitalized) }
        if recipe.forceInstrumental == false { parts.append("vocals allowed") }
        if let seed = recipe.seed { parts.append("seed \(seed)") }
        if let finetune = recipe.finetune {
            let name =
                MusicFinetuneStore.shared.finetune(withId: finetune.finetuneId)?.name
                ?? finetune.finetuneId
            parts.append(
                "finetune \(name) @ \(finetune.strength.formatted(.number.precision(.fractionLength(1))))"
            )
        }
        if !recipe.genres.isEmpty { parts.append(recipe.genres.joined(separator: ", ")) }
        return parts.joined(separator: " • ")
    }

    /// Where iteration starts. Every action here builds on this take rather than re-rolling.
    @ViewBuilder
    private var nextTakeMenu: some View {
        if let reference = candidate.reference, let recipe, !candidate.isExpired {
            Menu {
                if reference.plan != nil {
                    Button {
                        onEditPlan(reference, recipe)
                    } label: {
                        Label("Edit This Plan", systemImage: "slider.horizontal.3")
                    }
                    Button {
                        onKeepOpening(reference)
                    } label: {
                        Label("Keep the Opening…", systemImage: "scissors")
                    }
                }
                Button {
                    onSoundLike(reference)
                } label: {
                    Label("Sound Like This Take", systemImage: "ear.badge.waveform")
                }
            } label: {
                Label("Next Take", systemImage: "arrow.turn.down.right")
            }
            .menuStyle(.button)
            .buttonStyle(.glass)
            .fixedSize()
        } else if recipe != nil {
            Text("Not kept for reference")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .help(
                    "This take was generated without store_for_inpainting, so later takes can't build on it."
                )
        }
    }
}

/// Read-only rendering of a plan, section by section.
struct MusicPlanSummary: View {
    let plan: MusicCompositionPlan
    let reference: MusicReferenceTake?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(plan.chunks.enumerated()), id: \.offset) { index, chunk in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(index + 1).")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                    Text(TimeHelper.formatDuration(Double(chunk.durationMilliseconds) / 1_000))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    switch chunk {
                    case .audioReference(let range):
                        Label(
                            "Re-rendered \(TimeHelper.formatDuration(Double(range.startMilliseconds) / 1_000))–\(TimeHelper.formatDuration(Double(range.endMilliseconds) / 1_000)) of \(reference?.songId == range.songId ? (reference?.label ?? "a prior take") : "a prior take")",
                            systemImage: "waveform.badge.magnifyingglass"
                        )
                        .font(.caption)
                    case .generation(let generation):
                        VStack(alignment: .leading, spacing: 2) {
                            Text(generation.text).font(.caption)
                            if !generation.positiveStyles.isEmpty
                                || !generation.negativeStyles.isEmpty
                            {
                                Text(styleLine(generation))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            if let conditioning = generation.conditioningReference {
                                Text(
                                    "sounds like \(conditioning.songId == reference?.songId ? (reference?.label ?? "a prior take") : "a prior take") (\(generation.conditionStrength?.displayName.lowercased() ?? "medium"))"
                                )
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .textSelection(.enabled)
    }

    private func styleLine(_ chunk: MusicGenerationChunk) -> String {
        var parts: [String] = []
        if !chunk.positiveStyles.isEmpty {
            parts.append("+ " + chunk.positiveStyles.joined(separator: ", "))
        }
        if !chunk.negativeStyles.isEmpty {
            parts.append("− " + chunk.negativeStyles.joined(separator: ", "))
        }
        return parts.joined(separator: "   ")
    }
}
