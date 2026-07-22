// AdHocSoundViews.swift
// Extracted from AdHocAssetsView.swift (Phase 5 decomposition, issue #35).

import Common
import Foundation
import SwiftUI

private func adHocByteString(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter.string(fromByteCount: bytes)
}

struct AdHocSoundListView: View {

    private let server = CreatureServerClient.shared
    private let audioManager = AudioManager.shared

    @State private var sounds: [AdHocSoundEntry] = []
    @State private var isLoading = false
    @State private var errorAlert: ErrorAlert?
    @State private var preparingSound: String?
    @State private var playTask: Task<Void, Never>?
    @State private var soundToShare: String? = nil

    var body: some View {
        List {
            if isLoading && sounds.isEmpty {
                ProgressView("Loading ad-hoc sounds…")
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if sounds.isEmpty {
                ContentUnavailableView(
                    "No Ad-Hoc Sounds",
                    systemImage: "waveform",
                    description:
                        Text("Generate speech from the Live Magic console to see files here.")
                )
            } else {
                ForEach(
                    sounds.sorted {
                        ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast)
                    }
                ) { entry in
                    AdHocSoundRow(entry: entry, shareTrigger: $soundToShare) {
                        playLocally(entry: $0)
                    }
                }
            }
        }
        .shareableSoundFlow(fileName: $soundToShare)
        #if os(macOS)
            .listStyle(.inset)
        #elseif os(tvOS)
            .listStyle(.plain)
        #else
            .listStyle(.insetGrouped)
        #endif
        .navigationTitle("Ad-Hoc Sounds")
        .toolbar {
            Button {
                Task { await load(force: true) }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(isLoading)
            .help("Refresh the ad-hoc sound list")
        }
        .refreshable {
            await load(force: true)
        }
        .task {
            await load()
        }
        .errorAlert($errorAlert)
    }

    private func load(force: Bool = false) async {
        if isLoading && !force { return }
        isLoading = true
        let result = await server.listAdHocSounds()
        isLoading = false
        switch result {
        case .success(let list):
            sounds = list
            errorAlert = nil
        case .failure(let error):
            errorAlert = ErrorAlert(title: "Unable to Load", error: error)
        }
    }

    private func playLocally(entry: AdHocSoundEntry) {
        playTask?.cancel()
        playTask = Task {
            preparingSound = entry.sound.fileName
            let urlResult = server.getAdHocSoundURL(entry.sound.fileName)
            switch urlResult {
            case .success(let url):
                if entry.sound.fileName.lowercased().hasSuffix(".wav") {
                    let prepResult = await audioManager.prepareMonoPreview(
                        for: url, cacheKey: entry.sound.fileName)
                    switch prepResult {
                    case .success(let monoURL):
                        let armResult = audioManager.armPreviewPlayback(fileURL: monoURL)
                        switch armResult {
                        case .success:
                            _ = audioManager.startArmedPreview(in: 0.1)
                            preparingSound = nil
                        case .failure(let error):
                            presentError("Playback Error", message: "\(error)")
                        }
                    case .failure(let error):
                        presentError("Preparation Error", message: "\(error)")
                    }
                } else {
                    _ = audioManager.playURL(url)
                    preparingSound = nil
                }
            case .failure(let error):
                presentError(
                    "Unable to Download", message: ServerError.detailedMessage(from: error))
            }
        }
    }

    private func presentError(_ title: String, message: String) {
        errorAlert = ErrorAlert(title: title, message: message)
        preparingSound = nil
    }
}

private struct AdHocSoundRow: View {
    let entry: AdHocSoundEntry
    @Binding var shareTrigger: String?
    let playAction: (AdHocSoundEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.sound.fileName)
                    .font(.headline)
                Spacer()
                if let createdAt = entry.createdAt {
                    Text(adHocRelativeString(createdAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                Label(adHocByteString(Int64(entry.sound.size)), systemImage: "internaldrive")
                    .font(.caption)
                if !entry.sound.transcript.isEmpty {
                    Label("Transcript", systemImage: "text.alignleft")
                        .font(.caption)
                }
            }
            .foregroundStyle(.secondary)

            Text(entry.sound.transcript.isEmpty ? "No transcript saved" : entry.sound.transcript)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Text(entry.soundFilePath)
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(.vertical, 6)
        .contextMenu {
            Button {
                Pasteboard.copy(entry.soundFilePath)
            } label: {
                Label("Copy File Path", systemImage: "doc.on.doc")
            }
            Button {
                Pasteboard.copy(entry.animationId)
            } label: {
                Label("Copy Animation ID", systemImage: "rectangle.and.pencil.and.ellipsis")
            }
            Button {
                playAction(entry)
            } label: {
                Label("Play Locally", systemImage: "music.quarternote.3")
            }
            ShareableSoundButton(fileName: entry.sound.fileName, trigger: $shareTrigger)
        }
    }
}
