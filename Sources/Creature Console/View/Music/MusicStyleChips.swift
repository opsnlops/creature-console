import Common
import SwiftUI

/// A row of removable style chips with a field to add another. Enter commits; commas split.
struct MusicStyleChips: View {
    let title: String
    let placeholder: String
    @Binding var styles: [String]
    let tint: Color

    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !title.isEmpty {
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            MusicChipFlow(spacing: 6) {
                ForEach(styles, id: \.self) { style in
                    HStack(spacing: 4) {
                        Text(style)
                        Button {
                            styles.removeAll { $0 == style }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption2.bold())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(style)")
                    }
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .glassEffect(.regular.tint(tint.opacity(0.25)), in: .capsule)
                }
                TextField(placeholder, text: $draft)
                    .textFieldStyle(.plain)
                    .font(.caption)
                    .frame(minWidth: 120)
                    .onSubmit(commit)
                    .disabled(styles.count >= DialogLimits.maxMusicStyles)
            }
        }
    }

    private func commit() {
        let additions =
            draft
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.utf8.count <= DialogLimits.maxMusicStyleBytes }
        for addition in additions where !styles.contains(addition) {
            guard styles.count < DialogLimits.maxMusicStyles else { break }
            styles.append(addition)
        }
        draft = ""
    }
}

/// Lays chips out left to right, wrapping to new lines as the width runs out.
struct MusicChipFlow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        return arrange(width: width, subviews: subviews).size
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        let arrangement = arrange(width: bounds.width, subviews: subviews)
        for (subview, origin) in zip(subviews, arrangement.origins) {
            subview.place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                proposal: .unspecified)
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: maxX, height: y + rowHeight), origins)
    }
}
