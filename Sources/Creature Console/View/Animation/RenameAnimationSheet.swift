/// Sheet for renaming an animation; the new title is saved to the server immediately.
import SwiftUI

struct RenameAnimationSheet: View {
    @Binding var title: String
    let originalTitle: String
    let onCancel: () -> Void
    let onSave: () -> Void

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rename Animation")
                .font(.title2.bold())

            Text("Update the animation name. This change is saved to the server immediately.")
                .font(.callout)
                .foregroundStyle(.secondary)

            TextField("Animation Name", text: $title)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    guard canSave else { return }
                    onSave()
                }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                Button("Save") {
                    onSave()
                }
                .buttonStyle(.glassProminent)
                .disabled(!canSave)
            }
        }
        .padding(24)
        .frame(minWidth: 360)
    }

    private var canSave: Bool {
        !trimmedTitle.isEmpty && trimmedTitle != originalTitle
    }
}
