import Common
import SwiftUI

private typealias CreatureAnimation = Common.Animation

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

private func adHocRelativeString(_ date: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .short
    return formatter.localizedString(for: date, relativeTo: Date())
}

private func adHocByteString(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter.string(fromByteCount: bytes)
}

private func copyToClipboard(_ text: String) {
    #if canImport(UIKit)
        UIPasteboard.general.string = text
    #elseif canImport(AppKit)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    #else
        _ = text
    #endif
}

struct AdHocAnimationListView: View {

    private let server = CreatureServerClient.shared

    @State private var animations: [AdHocAnimationSummary] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            if isLoading && animations.isEmpty {
                ProgressView("Loading ad-hoc animations…")
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if animations.isEmpty {
                ContentUnavailableView(
                    "No Ad-Hoc Animations",
                    systemImage: "sparkles",
                    description:
                        Text("Generate one from the Live Magic console to see it here.")
                )
            } else {
                ForEach(
                    animations.sorted {
                        ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast)
                    }
                ) { animation in
                    NavigationLink {
                        AdHocAnimationDetailView(animationId: animation.animationId)
                    } label: {
                        AdHocAnimationRow(animation: animation)
                    }
                }
            }
        }
        #if os(macOS)
            .listStyle(.inset)
        #else
            .listStyle(.insetGrouped)
        #endif
        .navigationTitle("Ad-Hoc Animations")
        .toolbar {
            Button {
                Task { await load(force: true) }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(isLoading)
        }
        .refreshable {
            await load(force: true)
        }
        .task {
            await load()
        }
        .alert(
            "Unable to Load",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func load(force: Bool = false) async {
        if isLoading && !force { return }
        await MainActor.run { isLoading = true }
        let result = await server.listAdHocAnimations()
        await MainActor.run {
            isLoading = false
            switch result {
            case .success(let list):
                animations = list
                errorMessage = nil
            case .failure(let error):
                errorMessage = ServerError.detailedMessage(from: error)
            }
        }
    }
}

private struct AdHocAnimationRow: View {
    let animation: AdHocAnimationSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(animation.metadata.title)
                    .font(.headline)
                Spacer()
                if let createdAt = animation.createdAt {
                    Text(adHocRelativeString(createdAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text(animation.metadata.note)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack(spacing: 12) {
                Label("\(animation.metadata.numberOfFrames) frames", systemImage: "film")
                    .font(.caption)
                Label("\(animation.metadata.millisecondsPerFrame)ms", systemImage: "speedometer")
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        .contextMenu {
            Button {
                copyToClipboard(animation.animationId)
            } label: {
                Label("Copy Animation ID", systemImage: "doc.on.doc")
            }
        }
    }
}

private struct AdHocAnimationDetailView: View {

    let animationId: AnimationIdentifier
    @State private var animation: CreatureAnimation?
    @State private var errorMessage: String?
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading animation…")
            } else if let errorMessage {
                ContentUnavailableView(
                    "Unable to Load",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else if let animation {
                AnimationEditor(animation: animation, readOnly: true)
            }
        }
        .navigationTitle("Ad-Hoc Animation")
        .task(id: animationId) {
            await load()
        }
    }

    private func load() async {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        let result = await CreatureServerClient.shared.getAdHocAnimation(animationId: animationId)
        await MainActor.run {
            isLoading = false
            switch result {
            case .success(let animation):
                self.animation = animation
            case .failure(let error):
                errorMessage = ServerError.detailedMessage(from: error)
            }
        }
    }
}

struct AdHocSoundListView: View {

    private let server = CreatureServerClient.shared
    private let audioManager = AudioManager.shared

    @State private var sounds: [AdHocSoundEntry] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var preparingSound: String?
    @State private var playTask: Task<Void, Never>?
    @State private var alertTitle: String = ""
    @State private var alertMessage: String = ""
    @State private var showAlert: Bool = false

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
                    AdHocSoundRow(entry: entry) { playLocally(entry: $0) }
                }
            }
        }
        #if os(macOS)
            .listStyle(.inset)
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
        }
        .refreshable {
            await load(force: true)
        }
        .task {
            await load()
        }
        .alert(
            "Unable to Load",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func load(force: Bool = false) async {
        if isLoading && !force { return }
        await MainActor.run { isLoading = true }
        let result = await server.listAdHocSounds()
        await MainActor.run {
            isLoading = false
            switch result {
            case .success(let list):
                sounds = list
                errorMessage = nil
            case .failure(let error):
                errorMessage = ServerError.detailedMessage(from: error)
            }
        }
    }

    private func playLocally(entry: AdHocSoundEntry) {
        playTask?.cancel()
        playTask = Task {
            await MainActor.run { preparingSound = entry.sound.fileName }
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
                            await MainActor.run { preparingSound = nil }
                        case .failure(let error):
                            await presentError("Playback Error", message: "\(error)")
                        }
                    case .failure(let error):
                        await presentError("Preparation Error", message: "\(error)")
                    }
                } else {
                    _ = audioManager.playURL(url)
                    await MainActor.run { preparingSound = nil }
                }
            case .failure(let error):
                await presentError(
                    "Unable to Download", message: ServerError.detailedMessage(from: error))
            }
        }
    }

    private func presentError(_ title: String, message: String) async {
        await MainActor.run {
            alertTitle = title
            alertMessage = message
            showAlert = true
            preparingSound = nil
        }
    }
}

private struct AdHocSoundRow: View {
    let entry: AdHocSoundEntry
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
                copyToClipboard(entry.soundFilePath)
            } label: {
                Label("Copy File Path", systemImage: "doc.on.doc")
            }
            Button {
                copyToClipboard(entry.animationId)
            } label: {
                Label("Copy Animation ID", systemImage: "rectangle.and.pencil.and.ellipsis")
            }
            Button {
                playAction(entry)
            } label: {
                Label("Play Locally", systemImage: "music.quarternote.3")
            }
        }
    }
}
