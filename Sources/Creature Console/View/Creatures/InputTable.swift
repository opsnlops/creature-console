import Common
import Foundation
import OSLog
import SwiftData
import SwiftUI

#if os(macOS)
    import AppKit
#elseif os(iOS)
    import UIKit
#endif

// Legacy InputTable for backwards compatibility
struct InputTable: View {
    var creature: Creature
    let numberFormatter = Decimal.FormatStyle.number

    var body: some View {
        if creature.inputs.isEmpty {
            Text("Creature has no inputs defined")
        } else {
            #if os(tvOS)
                // tvOS doesn't support Table, use List instead
                List(creature.inputs) { input in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(input.name)
                            .font(.headline)
                        HStack {
                            Text("Slot: \(input.slot)")
                            Spacer()
                            Text("Width: \(input.width)")
                            Spacer()
                            Text("Axis: \(input.joystickAxis)")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }
            #else
                Table(creature.inputs) {
                    TableColumn("Name", value: \.name)
                        .width(min: 120, ideal: 200)
                    TableColumn("Slot") { input in
                        Text(input.slot.formatted(.number))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .width(min: 20, ideal: 40)
                    TableColumn("Width") { input in
                        Text(input.width.formatted(.number))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .width(min: 20, ideal: 40)
                    TableColumn("Joystick Axis") { input in
                        Text(input.joystickAxis.formatted(.number))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .width(min: 20, ideal: 40)
                }
            #endif
        }
    }
}

struct CreatureConfigDisplay: View {
    var creature: Creature

    @Query(sort: \AnimationMetadataModel.title, order: .forward)
    private var animations: [AnimationMetadataModel]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Creature Configuration")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text(
                        "These values are read-only and managed by the Controller. The Creature's JSON file is the source of truth."
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 8)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Overview")
                        .font(.headline)

                    creatureIdRow()
                    configRow(label: "Name", value: creature.name)
                    configRow(label: "Channel Offset", value: String(creature.channelOffset))
                    configRow(label: "Mouth Slot", value: String(creature.mouthSlot))
                    configRow(label: "Audio Channel", value: String(creature.audioChannel))
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(12)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Loops")
                        .font(.headline)

                    configRow(
                        label: "Speech Loops",
                        value: "\(creature.speechLoopAnimationIds.count)"
                    )
                    if !creature.speechLoopAnimationIds.isEmpty {
                        loopList(
                            title: "Speech Loop IDs",
                            values: creature.speechLoopAnimationIds
                        )
                    }

                    configRow(
                        label: "Idle Loops",
                        value: "\(creature.idleAnimationIds.count)"
                    )
                    if !creature.idleAnimationIds.isEmpty {
                        loopList(
                            title: "Idle Loop IDs",
                            values: creature.idleAnimationIds
                        )
                    }
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(12)

                if creature.inputs.isEmpty {
                    // Empty state
                    VStack(spacing: 16) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("No Input Channels Configured")
                            .font(.title3)
                            .foregroundColor(.secondary)
                        Text("This creature doesn't have any input channels defined.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(32)
                } else {
                    // Input table/list
                    #if os(tvOS)
                        // tvOS version with List
                        List(creature.inputs) { input in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(input.name)
                                    .font(.headline)

                                HStack(spacing: 24) {
                                    VStack(alignment: .leading) {
                                        Text("Slot")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text("\(input.slot)")
                                            .font(.body)
                                    }

                                    VStack(alignment: .leading) {
                                        Text("Width")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text("\(input.width)")
                                            .font(.body)
                                    }

                                    VStack(alignment: .leading) {
                                        Text("Joystick Axis")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text("\(input.joystickAxis)")
                                            .font(.body)
                                    }

                                    Spacer()
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .frame(minHeight: 300)
                    #else
                        // macOS/iOS version with Table
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Input Channels (\(creature.inputs.count))")
                                .font(.headline)

                            Table(creature.inputs) {
                                TableColumn("Channel Name", value: \.name)
                                    .width(min: 120, ideal: 200)
                                TableColumn("Slot") { input in
                                    Text(String(input.slot))
                                        .frame(maxWidth: .infinity, alignment: .center)
                                }
                                .width(min: 60, ideal: 80)
                                TableColumn("Width") { input in
                                    Text(String(input.width))
                                        .frame(maxWidth: .infinity, alignment: .center)
                                }
                                .width(min: 60, ideal: 80)
                                TableColumn("Joystick Axis") { input in
                                    Text(String(input.joystickAxis))
                                        .frame(maxWidth: .infinity, alignment: .center)
                                }
                                .width(min: 100, ideal: 120)
                            }
                            .frame(minHeight: 300)
                        }
                    #endif
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Raw Creature JSON")
                            .font(.headline)
                        Spacer()
                        #if !os(tvOS)
                            Button(action: {
                                if let creatureJSON {
                                    copyToClipboard(creatureJSON)
                                }
                            }) {
                                Image(systemName: "doc.on.doc")
                            }
                            .buttonStyle(.plain)
                            .disabled(creatureJSON == nil)
                            .help("Copy Creature JSON")
                        #endif
                    }
                    ScrollView(.vertical) {
                        Text(creatureJSON ?? "Unable to encode creature JSON.")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    }
                    .frame(minHeight: 220)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(12)
                }
            }
            .padding()
        }
        .bottomToolbarInset()
        .navigationTitle("\(creature.name) Config")
        #if os(macOS)
            .navigationSubtitle("\(creature.inputs.count) input channels configured")
        #endif
    }

    @ViewBuilder
    private func configRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .fontWeight(.medium)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private func creatureIdRow() -> some View {
        HStack {
            Text("Creature ID")
                .fontWeight(.medium)
            Spacer()
            Text(creature.id)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            #if !os(tvOS)
                Button(action: {
                    copyToClipboard(creature.id)
                }) {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.plain)
                .help("Copy Creature ID")
            #endif
        }
    }

    @ViewBuilder
    private func loopList(title: String, values: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            ForEach(values, id: \.self) { value in
                Text(resolvedAnimationLabel(for: value))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var creatureJSON: String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(creature) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func resolvedAnimationLabel(for id: AnimationIdentifier) -> String {
        if let animation = animations.first(where: { $0.id == id }) {
            return "\(animation.title) (\(id))"
        }
        return "Unknown Animation (\(id))"
    }

    private func copyToClipboard(_ value: String) {
        #if os(macOS)
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(value, forType: .string)
        #elseif os(iOS)
            UIPasteboard.general.string = value
        #endif
    }
}

// Wrapper for older call sites
struct InputTableView: View {
    var creature: Creature

    var body: some View {
        CreatureConfigDisplay(creature: creature)
    }
}

#Preview("Input Table") {
    InputTable(creature: Creature.mock())
}

#Preview("Input Table View") {
    NavigationView {
        CreatureConfigDisplay(creature: Creature.mock())
    }
}
