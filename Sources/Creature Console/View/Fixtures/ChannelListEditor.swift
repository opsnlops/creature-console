import Common
import SwiftUI

/// CRUD list of `FixtureChannel` rows. Each row exposes name / offset / kind. The
/// surrounding `FixtureEditor` is responsible for save-time validation; this view does
/// minimal client-side hinting (duplicate name warning).
struct ChannelListEditor: View {

    @Binding var fixture: Common.DmxFixture

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Channels").font(.headline)
                Spacer()
                Text("\(fixture.channels.count) / 64 max")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(action: addChannel) {
                    Label("Add Channel", systemImage: "plus.circle")
                }
                .disabled(fixture.channels.count >= 64)
            }

            if fixture.channels.isEmpty {
                Text("A fixture needs at least one channel.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if hasDuplicateName {
                Label(
                    "Channel names must be unique within the fixture.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundStyle(.orange)
                .font(.caption)
            }

            LazyVStack(spacing: 8) {
                ForEach(Array(fixture.channels.enumerated()), id: \.offset) { index, _ in
                    channelRow(at: index)
                }
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func channelRow(at index: Int) -> some View {
        HStack(spacing: 12) {
            TextField(
                "Name",
                text: Binding(
                    get: { fixture.channels[index].name },
                    set: { fixture.channels[index].name = $0 }
                )
            )
            .textFieldStyle(.roundedBorder)
            .frame(minWidth: 100, idealWidth: 160)

            Stepper(
                value: Binding<Int>(
                    get: { Int(fixture.channels[index].offset) },
                    set: { newValue in
                        fixture.channels[index].offset = UInt16(clamping: max(0, newValue))
                    }
                ),
                in: 0...511
            ) {
                HStack {
                    Text("Offset:")
                    Text("\(fixture.channels[index].offset)")
                        .font(.system(.body, design: .monospaced))
                }
            }
            .frame(maxWidth: 240)

            Picker(
                "Kind",
                selection: Binding(
                    get: { fixture.channels[index].kind },
                    set: { fixture.channels[index].kind = $0 }
                )
            ) {
                ForEach(FixtureChannelKind.all, id: \.self) { kind in
                    Text(kind).tag(kind)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 180)

            Spacer()

            Button(role: .destructive) {
                fixture.channels.remove(at: index)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
    }

    private var hasDuplicateName: Bool {
        let names = fixture.channels.map { $0.name }
        return names.count != Set(names).count
    }

    private func addChannel() {
        let nextOffset = (fixture.channels.map { Int($0.offset) }.max() ?? -1) + 1
        let name = "channel\(fixture.channels.count + 1)"
        fixture.channels.append(
            FixtureChannel(
                offset: UInt16(clamping: nextOffset),
                name: name,
                kind: FixtureChannelKind.generic
            )
        )
    }
}
