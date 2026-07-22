// CreatureRuntimeSummary.swift
// Extracted from CreatureDetail.swift (Phase 5 decomposition, issue #35).

import Common
import Foundation
import SwiftUI

struct CreatureRuntimeSummary: View {
    let runtime: CreatureRuntime?
    let lastUpdated: Date?

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Runtime")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                if let lastUpdated {
                    Text("Last updated: \(dateFormatter.string(from: lastUpdated))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let runtime {
                runtimeDetails(runtime)
            } else {
                Text("Runtime data not available yet.")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }

    @ViewBuilder
    private func runtimeDetails(_ runtime: CreatureRuntime) -> some View {
        #if os(macOS)
            VStack(alignment: .leading, spacing: 10) {
                runtimeSectionMac(
                    "Activity",
                    items: [
                        ("State", runtime.activity?.state.rawValue),
                        ("Reason", runtime.activity?.reason?.rawValue),
                        ("Animation ID", runtime.activity?.animationId),
                        ("Session ID", runtime.activity?.sessionId),
                        ("Started", formattedDate(runtime.activity?.startedAt)),
                        ("Updated", formattedDate(runtime.activity?.updatedAt)),
                    ]
                )

                runtimeSectionMac(
                    "Idle",
                    items: [
                        ("Enabled", runtime.idleEnabled.map { $0 ? "true" : "false" })
                    ]
                )

                runtimeSectionMac(
                    "Ownership",
                    items: [
                        ("BGM Owner", runtime.bgmOwner)
                    ]
                )

                if let lastError = runtime.lastError {
                    runtimeSectionMac(
                        "Last Error",
                        items: [
                            ("Message", lastError.message),
                            ("Timestamp", formattedDate(lastError.timestamp)),
                        ]
                    )
                }

                if let counters = runtime.counters {
                    runtimeSectionMac(
                        "Counters",
                        items: [
                            ("Sessions Started", counters.sessionsStartedTotal.map { "\($0)" }),
                            ("Sessions Cancelled", counters.sessionsCancelledTotal.map { "\($0)" }),
                            ("Idle Started", counters.idleStartedTotal.map { "\($0)" }),
                            ("Idle Stopped", counters.idleStoppedTotal.map { "\($0)" }),
                            ("Idle Toggles", counters.idleTogglesTotal.map { "\($0)" }),
                            (
                                "Skips Missing Creature",
                                counters.skipsMissingCreatureTotal.map { "\($0)" }
                            ),
                            ("BGM Takeovers", counters.bgmTakeoversTotal.map { "\($0)" }),
                            ("Audio Resets", counters.audioResetsTotal.map { "\($0)" }),
                        ]
                    )
                }
            }
        #else
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("Activity")
                VStack(alignment: .leading, spacing: 8) {
                    runtimeRow("State", value: runtime.activity?.state.rawValue)
                    runtimeRow("Reason", value: runtime.activity?.reason?.rawValue)
                    runtimeRow("Animation ID", value: runtime.activity?.animationId)
                    runtimeRow("Session ID", value: runtime.activity?.sessionId)
                    runtimeRow("Started", value: formattedDate(runtime.activity?.startedAt))
                    runtimeRow("Updated", value: formattedDate(runtime.activity?.updatedAt))
                }

                sectionTitle("Idle")
                runtimeRow("Enabled", value: runtime.idleEnabled.map { $0 ? "true" : "false" })

                sectionTitle("Ownership")
                runtimeRow("BGM Owner", value: runtime.bgmOwner)

                if let lastError = runtime.lastError {
                    sectionTitle("Last Error")
                    VStack(alignment: .leading, spacing: 8) {
                        runtimeRow("Message", value: lastError.message)
                        runtimeRow("Timestamp", value: formattedDate(lastError.timestamp))
                    }
                }

                if let counters = runtime.counters {
                    sectionTitle("Counters")
                    VStack(alignment: .leading, spacing: 8) {
                        runtimeRow(
                            "Sessions Started",
                            value: counters.sessionsStartedTotal.map { "\($0)" }
                        )
                        runtimeRow(
                            "Sessions Cancelled",
                            value: counters.sessionsCancelledTotal.map { "\($0)" }
                        )
                        runtimeRow(
                            "Idle Started",
                            value: counters.idleStartedTotal.map { "\($0)" }
                        )
                        runtimeRow(
                            "Idle Stopped",
                            value: counters.idleStoppedTotal.map { "\($0)" }
                        )
                        runtimeRow(
                            "Idle Toggles",
                            value: counters.idleTogglesTotal.map { "\($0)" }
                        )
                        runtimeRow(
                            "Skips Missing Creature",
                            value: counters.skipsMissingCreatureTotal.map { "\($0)" }
                        )
                        runtimeRow(
                            "BGM Takeovers",
                            value: counters.bgmTakeoversTotal.map { "\($0)" }
                        )
                        runtimeRow(
                            "Audio Resets",
                            value: counters.audioResetsTotal.map { "\($0)" }
                        )
                    }
                }
            }
        #endif
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            #if os(macOS)
                .font(.caption)
            #else
                .font(.subheadline)
            #endif
            .foregroundStyle(.secondary)
    }

    private func runtimeRow(_ label: String, value: String?) -> some View {
        LabeledContent(label) {
            Text(value ?? "n/a")
        }
    }

    #if os(macOS)
        private var runtimeGridColumns: [GridItem] {
            [
                GridItem(.flexible(minimum: 140), alignment: .leading),
                GridItem(.flexible(minimum: 140), alignment: .leading),
            ]
        }

        @ViewBuilder
        private func runtimeSectionMac(_ title: String, items: [(String, String?)]) -> some View {
            sectionTitle(title)
            LazyVGrid(columns: runtimeGridColumns, alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(spacing: 6) {
                        Text(item.0)
                            .foregroundStyle(.secondary)
                        Text(item.1 ?? "n/a")
                    }
                    .font(.callout)
                }
            }
        }
    #endif

    private func formattedDate(_ date: Date?) -> String? {
        guard let date else { return nil }
        return date.formatted(.dateTime.hour().minute().second())
    }
}
