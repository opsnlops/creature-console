import Common
import SwiftUI

struct LiveMagicPromptSheet: View {

    let mode: LiveMagicViewModel.PromptMode
    let creatures: [Creature]
    let isSubmitting: Bool
    let onCancel: () -> Void
    let onSubmit: (LiveMagicViewModel.PromptRequest) -> Void

    @State private var selectedCreature: Creature?
    @State private var scriptText: String = ""
    @State private var resumePlaylist: Bool = true
    @FocusState private var textIsFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                pickerSection
                textSection
                toggleSection
                Spacer()
                submitSection
            }
            .padding()
            .navigationTitle(mode.title)
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                        .disabled(isSubmitting)
                }
            }
        }
        .onAppear {
            if selectedCreature == nil {
                selectedCreature = creatures.first
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                textIsFocused = true
            }
        }
    }

    private var pickerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Creature")
                .font(.headline)
            Picker("Creature", selection: $selectedCreature) {
                ForEach(creatures, id: \.id) { creature in
                    Text(creature.name).tag(creature as Creature?)
                }
            }
            .pickerStyle(.menu)
        }
    }

    private var textSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Dialog")
                    .font(.headline)
                Spacer()
                Text("\(scriptText.count) chars")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $scriptText)
                    .focused($textIsFocused)
                    .frame(minHeight: 160)
                    .padding(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.secondary.opacity(0.15))
                    )

                if scriptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(
                        "Type the riff, story beat, or punchline. The server will handle audio, lips, and animation."
                    )
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 18)
                }
            }
        }
    }

    private var toggleSection: some View {
        Toggle(isOn: $resumePlaylist) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Resume playlist when finished")
                    .font(.headline)
                Text("Turn off if you're improvising between playlists or running standalone bits.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
    }

    private var submitSection: some View {
        HStack(spacing: 12) {
            Button(role: .cancel, action: onCancel) {
                Text("Close")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(isSubmitting)

            Button(action: submit) {
                if isSubmitting {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text(mode.submitLabel)
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSubmitDisabled)
        }
    }

    private var isSubmitDisabled: Bool {
        isSubmitting || selectedCreature == nil
            || scriptText
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() {
        guard let creature = selectedCreature else { return }
        let request = LiveMagicViewModel.PromptRequest(
            creature: creature,
            text: scriptText,
            resumePlaylist: resumePlaylist
        )
        onSubmit(request)
    }
}
