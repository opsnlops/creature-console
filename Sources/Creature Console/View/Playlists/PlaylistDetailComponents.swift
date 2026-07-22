// PlaylistDetailComponents.swift
// Extracted from PlaylistDetail.swift (Phase 5 decomposition, issue #35).

import Common
import SwiftUI

struct PlaylistItemRow: View {
    let item: PlaylistItem
    let animationName: String
    let percentage: Double
    let onWeightChanged: (UInt32) -> Void
    let onDelete: () -> Void

    @State private var editingWeight: String = ""
    @State private var isEditingWeight = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(animationName)
                    .font(.headline)

                Text("ID: \(item.animationId)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 8) {
                    if isEditingWeight {
                        TextField("Weight", text: $editingWeight)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                            .onSubmit {
                                submitWeightChange()
                            }

                        Button("✓") {
                            submitWeightChange()
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.green)
                        .help("Save the new weight")
                    } else {
                        Text("Weight: \(item.weight)")
                            .font(.subheadline)
                            .onTapGesture {
                                startEditingWeight()
                            }
                    }
                }

                Text(String(format: "%.1f%%", percentage))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button("Delete") {
                onDelete()
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.red)
        }
        .padding(.vertical, 8)
        .contextMenu {
            Button("Edit Weight") {
                startEditingWeight()
            }

            Divider()

            Button("Delete", role: .destructive) {
                onDelete()
            }
        }
    }

    private func startEditingWeight() {
        editingWeight = String(item.weight)
        isEditingWeight = true
    }

    private func submitWeightChange() {
        if let newWeight = UInt32(editingWeight) {
            onWeightChanged(newWeight)
        }
        isEditingWeight = false
    }
}

struct WeightDistributionView: View {
    let items: [PlaylistItem]
    let animations: [AnimationMetadataModel]

    private var totalWeight: UInt32 {
        items.reduce(0) { $0 + $1.weight }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                ForEach(items, id: \.id) { item in
                    let percentage = totalWeight > 0 ? Double(item.weight) / Double(totalWeight) : 0

                    Rectangle()
                        .fill(colorForAnimation(item.animationId))
                        .frame(width: max(percentage * 300, 4))
                        .help(
                            "\(animationName(for: item.animationId)): \(String(format: "%.1f%%", percentage * 100))"
                        )
                }
            }
            .frame(height: 20)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200))], spacing: 8) {
                ForEach(items, id: \.id) { item in
                    let percentage =
                        totalWeight > 0 ? Double(item.weight) / Double(totalWeight) * 100 : 0

                    HStack(spacing: 8) {
                        Rectangle()
                            .fill(colorForAnimation(item.animationId))
                            .frame(width: 12, height: 12)
                            .clipShape(RoundedRectangle(cornerRadius: 2))

                        Text(animationName(for: item.animationId))
                            .font(.caption)
                            .lineLimit(1)

                        Spacer()

                        Text(String(format: "%.1f%%", percentage))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func animationName(for id: AnimationIdentifier) -> String {
        animations.first(where: { $0.id == id })?.title ?? "Unknown"
    }

    private func colorForAnimation(_ id: AnimationIdentifier) -> Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .red, .pink, .indigo, .teal]
        let hash = abs(id.hashValue)
        return colors[hash % colors.count]
    }
}

struct AddAnimationToPlaylistView: View {
    let availableAnimations: [AnimationMetadata]
    let onAdd: (AnimationIdentifier, UInt32) -> Void

    @State private var selectedAnimation: AnimationMetadata?
    @State private var weight: String = "1"
    @State private var searchText = ""

    @Environment(\.dismiss) private var dismiss

    private var filteredAnimations: [AnimationMetadata] {
        if searchText.isEmpty {
            return availableAnimations
        } else {
            return availableAnimations.filter {
                $0.title.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Weight")
                        .font(.headline)

                    TextField("Enter weight (1-999)", text: $weight)
                        .textFieldStyle(.roundedBorder)

                    Text("Higher weights make animations more likely to be selected.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 8) {
                    Text("Select Animation")
                        .font(.headline)

                    if availableAnimations.isEmpty {
                        ContentUnavailableView {
                            Label("No Available Animations", systemImage: "music.note")
                        } description: {
                            Text("All animations are already in this playlist.")
                        }
                    } else {
                        List(filteredAnimations, id: \.id, selection: $selectedAnimation) {
                            animation in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(animation.title)
                                    .font(.headline)

                                Text(
                                    "Frames: \(animation.numberOfFrames) • Duration: \(animation.millisecondsPerFrame)ms/frame"
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)

                                if !animation.note.isEmpty {
                                    Text(animation.note)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .italic()
                                }
                            }
                            .padding(.vertical, 4)
                            .tag(animation)
                        }
                        .searchable(text: $searchText, prompt: "Search animations...")
                    }
                }
            }
            .padding()
            .navigationTitle("Add Animation")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addAnimation()
                    }
                    .disabled(selectedAnimation == nil || weight.isEmpty || UInt32(weight) == nil)
                }
            }
        }
    }

    private func addAnimation() {
        guard let animation = selectedAnimation,
            let weightValue = UInt32(weight),
            weightValue > 0
        else {
            return
        }

        onAdd(animation.id, weightValue)
        dismiss()
    }
}
