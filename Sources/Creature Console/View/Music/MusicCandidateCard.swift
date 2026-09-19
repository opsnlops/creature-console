import Common
import SwiftUI

/// One version of the piece: how it was made, and what can be done with it — listen against
/// the dialog, accept it for the render, or make it the piece being edited.
struct MusicCandidateCard: View {
    let candidate: DialogMusicCandidate
    let isCurrent: Bool
    let isEditing: Bool
    let isAccepted: Bool
    let hasAcceptedMusic: Bool
    let canPromote: Bool
    let isAuditioning: Bool

    let onAudition: () -> Void
    let onPromote: () -> Void
    let onMakeCurrent: () -> Void

    @State private var showsPlan = false

    private var recipe: DialogMusicRecipe? { candidate.result.recipe }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(candidate.label).font(.subheadline.bold())
                if isEditing {
                    Text("editing")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .glassEffect(.regular.tint(.accentColor.opacity(0.3)), in: .capsule)
                }
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
                        MusicPlanSummary(plan: plan, songId: recipe.songId)
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
                    "This temporary version expired on the server. Apply again to make a new one.",
                    systemImage: "clock.badge.exclamationmark"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            } else if !isCurrent {
                Label(
                    "Made for a different voice take than the accepted one — its timing won't match.",
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
                if !isEditing {
                    Button {
                        onMakeCurrent()
                    } label: {
                        Label("Edit This Version", systemImage: "slider.horizontal.3")
                    }
                    .buttonStyle(.glass)
                    .disabled(candidate.isExpired || candidate.editablePiece == nil)
                    .help(
                        candidate.editablePiece == nil
                            ? "This version wasn't kept at ElevenLabs, so it can't be refined."
                            : "Make this version the piece being edited")
                }
            }
        }
        .padding(12)
        .panelCard(cornerRadius: 10, tint: isAccepted ? .green : (isEditing ? .accentColor : nil))
    }

    private var headline: String {
        if let recipe, let title = recipe.songTitle { return title }
        if !candidate.result.prompt.isEmpty { return candidate.result.prompt }
        return "Composed from the piece's sections"
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
}

/// Read-only rendering of a plan, section by section.
struct MusicPlanSummary: View {
    let plan: MusicCompositionPlan
    /// The song this plan produced, so references into an earlier version are told apart.
    let songId: String

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
                            "Kept \(TimeHelper.formatDuration(Double(range.startMilliseconds) / 1_000))–\(TimeHelper.formatDuration(Double(range.endMilliseconds) / 1_000)) of the previous version",
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
                                    "sounds like \(conditioning.songId == songId ? "this version" : "the previous version") (\(generation.conditionStrength?.displayName.lowercased() ?? "medium"))"
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
