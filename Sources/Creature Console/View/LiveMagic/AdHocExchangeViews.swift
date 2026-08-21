// AdHocExchangeViews.swift
// Streamed ad-hoc exchanges — whole conversations, one stitched file each (issue #80).

import Combine
import Common
import Foundation
import SwiftUI

#if os(iOS) || os(macOS)
    import UniformTypeIdentifiers
#endif

extension Notification.Name {
    /// Posted when the server invalidates the ad-hoc exchange list
    /// (`cache_type: "ad-hoc-exchange-list"`) so open exchange views can refresh.
    static let adHocExchangeListChanged = Notification.Name("AdHocExchangeListChanged")
}

/// One exchange in one audio format, for the shared "Generate Shareable Version" flow.
struct ExchangeShareRequest: Equatable, Sendable {
    let sessionId: String
    let format: ExchangeAudioFormat
}

#if os(iOS) || os(macOS)
    extension ExchangeShareRequest: ShareableAudioRequest {
        var contentType: UTType {
            switch format {
            case .mp3: .mp3
            case .ogg: .oggAudio
            case .wav: .wav
            }
        }

        func download(using server: CreatureServerClient) async -> Result<
            CreatureServerClient.ShareableSound, ServerError
        > {
            await server.downloadExchangeAudio(sessionId: sessionId, format: format)
        }
    }
#else
    extension ExchangeShareRequest: ShareableAudioRequest {}
#endif

struct AdHocExchangeListView: View {

    private let server = CreatureServerClient.shared

    @State private var exchanges: [AdHocExchange] = []
    @State private var isLoading = false
    @State private var errorAlert: ErrorAlert?
    @State private var shareRequest: ExchangeShareRequest? = nil

    var body: some View {
        List {
            if isLoading && exchanges.isEmpty {
                ProgressView("Loading exchanges…")
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if exchanges.isEmpty {
                ContentUnavailableView(
                    "No Exchanges",
                    systemImage: "bubble.left.and.bubble.right",
                    description:
                        Text(
                            "When creature-agent has a creature talk, each streamed conversation shows up here."
                        )
                )
            } else {
                ForEach(
                    exchanges.sorted {
                        ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast)
                    }
                ) { exchange in
                    AdHocExchangeRow(exchange: exchange, shareTrigger: $shareRequest)
                }
            }
        }
        .shareableAudioFlow(request: $shareRequest)
        #if os(macOS)
            .listStyle(.inset)
        #elseif os(tvOS)
            .listStyle(.plain)
        #else
            .listStyle(.insetGrouped)
        #endif
        .navigationTitle("Exchanges")
        .toolbar {
            Button {
                Task { await load(force: true) }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(isLoading)
            .help("Refresh the exchange list")
        }
        .refreshable {
            await load(force: true)
        }
        .task {
            await load()
        }
        .onReceive(NotificationCenter.default.publisher(for: .adHocExchangeListChanged)) { _ in
            Task { await load(force: true) }
        }
        .errorAlert($errorAlert)
    }

    private func load(force: Bool = false) async {
        if isLoading && !force { return }
        isLoading = true
        let result = await server.listAdHocExchanges()
        isLoading = false
        switch result {
        case .success(let list):
            exchanges = list
            errorAlert = nil
        case .failure(let error):
            errorAlert = ErrorAlert(title: "Unable to Load", error: error)
        }
    }
}

private struct AdHocExchangeRow: View {
    let exchange: AdHocExchange
    @Binding var shareTrigger: ExchangeShareRequest?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(exchange.creatureName.isEmpty ? "Unknown Creature" : exchange.creatureName)
                    .font(.headline)
                Label(exchange.status.displayName, systemImage: exchange.status.symbolName)
                    .labelStyle(.titleAndIcon)
                    .font(.caption)
                    .foregroundStyle(exchange.status.tint)
                Spacer()
                if let createdAt = exchange.createdAt {
                    Text(adHocRelativeString(createdAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                if exchange.durationMs > 0 {
                    Label(
                        TimeHelper.formatDuration(Double(exchange.durationMs) / 1000.0),
                        systemImage: "clock"
                    )
                    .font(.caption)
                }
                if !exchange.parts.isEmpty {
                    Label("\(exchange.parts.count) sentences", systemImage: "text.bubble")
                        .font(.caption)
                }
            }
            .foregroundStyle(.secondary)

            Text(exchange.transcript.isEmpty ? "Nothing said yet" : exchange.transcript)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Text(exchange.sessionId)
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(.vertical, 6)
        .contextMenu {
            // Audio isn't downloadable until the session finishes — the server
            // answers 409 while it's still streaming. `partial` is fine: whatever
            // sentences rendered are in the stitched file.
            ShareableAudioButton(
                request: ExchangeShareRequest(sessionId: exchange.sessionId, format: .mp3),
                trigger: $shareTrigger
            )
            .disabled(exchange.status == .streaming)
            ShareableAudioButton(
                request: ExchangeShareRequest(sessionId: exchange.sessionId, format: .ogg),
                title: "Generate Ogg/Opus Version…",
                trigger: $shareTrigger
            )
            .disabled(exchange.status == .streaming)
            ShareableAudioButton(
                request: ExchangeShareRequest(sessionId: exchange.sessionId, format: .wav),
                title: "Download Stitched WAV…",
                trigger: $shareTrigger
            )
            .disabled(exchange.status == .streaming)
            Button {
                Pasteboard.copy(exchange.sessionId)
            } label: {
                Label("Copy Session ID", systemImage: "doc.on.doc")
            }
            Button {
                Pasteboard.copy(exchange.transcript)
            } label: {
                Label("Copy Transcript", systemImage: "text.alignleft")
            }
            .disabled(exchange.transcript.isEmpty)
        }
    }
}

extension ExchangeStatus {
    fileprivate var symbolName: String {
        switch self {
        case .streaming: "dot.radiowaves.left.and.right"
        case .ready: "checkmark.circle.fill"
        case .partial: "exclamationmark.triangle.fill"
        case .failed: "xmark.octagon.fill"
        case .unknown: "questionmark.circle"
        }
    }

    fileprivate var tint: Color {
        switch self {
        case .streaming: .blue
        case .ready: .green
        case .partial: .orange
        case .failed: .red
        case .unknown: .secondary
        }
    }

    fileprivate var displayName: String {
        rawValue.capitalized
    }
}
