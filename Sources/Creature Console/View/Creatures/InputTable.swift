import Common
import Foundation
import OSLog
import SwiftUI

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

// New dedicated view for Input Configuration
struct InputTableView: View {
    var creature: Creature

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Input Configuration")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text(
                        "These values are read-only and managed by the Controller. The Creature's JSON file is the source of truth."
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 8)
                }

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
            }
            .padding()
        }
        .navigationTitle("\(creature.name) Inputs")
        #if os(macOS)
            .navigationSubtitle("\(creature.inputs.count) input channels configured")
        #endif
    }
}

#Preview("Input Table") {
    InputTable(creature: Creature.mock())
}

#Preview("Input Table View") {
    NavigationView {
        InputTableView(creature: Creature.mock())
    }
}
