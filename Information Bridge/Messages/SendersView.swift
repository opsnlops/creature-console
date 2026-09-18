import SwiftUI

/// The numbers whose texts are read without a card mapped to them: the carriers, and
/// whatever April allows. Below them, who texted lately and was skipped unread - a number,
/// how often, how lately, never the words - so allowing one is a name and a click, not a
/// number copied off her phone. What an allowed sender says is read for a delivery only.
struct SendersView: View {
    @Bindable var store: BridgeStore
    @State private var newHandle = ""
    @State private var newName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(
                "Texts from these numbers are read - by the model on this Mac, for a delivery at the house - even with no card mapped. A person is mapped in People, not allowed here."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(12)
            List {
                Section("Read") {
                    ForEach(store.messagesSenders) { sender in
                        SenderRow(sender: sender, store: store)
                    }
                    HStack(spacing: 8) {
                        TextField("number or short code", text: $newHandle)
                            .font(.system(.body, design: .monospaced))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 180)
                            .onSubmit(add)
                        TextField("what the birds call it", text: $newName)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(add)
                        Button("Add", systemImage: "plus") { add() }
                            .buttonStyle(.glass)
                            .controlSize(.small)
                            .disabled(newHandle.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .padding(.vertical, 2)
                }
                Section("Texted lately, not read") {
                    if store.skippedSenders.isEmpty {
                        Text("Nobody unmapped has texted in the last two weeks.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(store.skippedSenders) { skipped in
                        SkippedRow(skipped: skipped, store: store)
                    }
                }
            }
        }
        .frame(minWidth: 560, minHeight: 400)
        .navigationTitle("Senders")
    }

    private func add() {
        let handle = newHandle.trimmingCharacters(in: .whitespaces)
        guard !handle.isEmpty else { return }
        store.allowSender(handle: handle, name: newName)
        newHandle = ""
        newName = ""
    }
}

private struct SenderRow: View {
    let sender: TextSender
    let store: BridgeStore

    var body: some View {
        HStack(spacing: 12) {
            Text(sender.handle)
                .font(.system(.body, design: .monospaced))
                .frame(width: 180, alignment: .leading)
            Text(sender.name)
                .fontWeight(.medium)
            Spacer()
            Button("Stop reading", systemImage: "xmark.circle") {
                store.disallowSender(sender)
            }
            .buttonStyle(.glass)
            .controlSize(.small)
        }
        .padding(.vertical, 2)
    }
}

private struct SkippedRow: View {
    let skipped: SkippedSender
    let store: BridgeStore
    @State private var name = ""

    var body: some View {
        HStack(spacing: 12) {
            Text(skipped.handle)
                .font(.system(.body, design: .monospaced))
                .frame(width: 180, alignment: .leading)
            Text(
                "\(skipped.count) text\(skipped.count == 1 ? "" : "s"), last \(skipped.lastAt.formatted(.relative(presentation: .named)))"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(width: 160, alignment: .leading)
            TextField("what the birds call it", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(allow)
            Button("Read", systemImage: "checkmark.circle") { allow() }
                .buttonStyle(.glass)
                .controlSize(.small)
        }
        .padding(.vertical, 2)
    }

    private func allow() {
        store.allowSender(handle: skipped.handle, name: name)
    }
}
