import AVFoundation
import AVKit
import Common
import Foundation
import OSLog
import Accelerate
import AudioToolbox
#if os(iOS)
import UIKit
#endif

@MainActor
class AudioManager: ObservableObject {

    // Only one of these can / should exist, so let's use the Singleton pattern
    static let shared = AudioManager()

    let server = CreatureServerClient.shared

    private var player: AVPlayer?
    private var audioPlayer: AVAudioPlayer?
    private var previewEngine: AVAudioEngine?
    private var previewPlayer: AVAudioPlayerNode?
    let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "AudioManager")

    /// The most recent error emitted by the audio manager. Observe this in the UI to present errors.
    @Published var lastError: AudioError?

    /// Keep a strong reference to the armed preview file so it remains valid during playback.
    private var previewFile: AVAudioFile?

    /// Report an error by logging it and publishing to the UI via `lastError`.
    private func reportError(_ error: AudioError, file: StaticString = #fileID, function: StaticString = #function, line: UInt = #line) {
        logger.error("Audio error reported at \(file, privacy: .public):\(line) in \(function, privacy: .public) — \(String(describing: error))")
        self.lastError = error
    }

    @Published var volume: Float {

        // If the user updates the volume, update the preferences
        didSet {
            UserDefaults.standard.set(Double(volume), forKey: "audioVolume")
            self.audioPlayer?.volume = volume
            self.player?.volume = volume
            self.previewPlayer?.volume = volume
        }
    }

    // This is private to make it impossible to make more than one
    private init() {

        if let storedDouble = UserDefaults.standard.object(forKey: "audioVolume") as? Double {
            self.volume = Float(storedDouble)
        } else if let storedFloat = UserDefaults.standard.object(forKey: "audioVolume") as? Float {
            self.volume = storedFloat
        } else {
            self.volume = 1.0
            UserDefaults.standard.set(1.0, forKey: "audioVolume")
        }

        #if os(iOS)
            do {
                try AVAudioSession.sharedInstance().setCategory(
                    .playback, mode: .default, options: [])
                try AVAudioSession.sharedInstance().setActive(true)
            } catch {
                print("Failed to set audio session category.")
            }
        #endif

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(userDefaultsDidChange(_:)),
            name: UserDefaults.didChangeNotification,
            object: nil
        )
    }


    func playURL(_ url: URL) -> Result<String, AudioError> {

        logger.debug("Attempting to play \(url)")

        let asset = AVURLAsset(url: url)
        let playerItem = AVPlayerItem(asset: asset)

        self.player = AVPlayer(playerItem: playerItem)
        self.player?.volume = volume
        player?.play()

        return .success("Played \(url)")

    }


    func playBundledSound(name: String, extension: String) -> Result<String, AudioError> {
        guard let url = Bundle.main.url(forResource: name, withExtension: `extension`) else {
            let err: AudioError = .fileNotFound("Couldn't find the bundled sound file!")
            logger.error("Couldn't find the bundled sound file.")
            reportError(err)
            return .failure(err)
        }

        do {
            self.audioPlayer = try AVAudioPlayer(contentsOf: url)
            self.audioPlayer?.volume = volume
            self.audioPlayer?.play()

            return .success("File queued up to play!")
        } catch {
            let err: AudioError = .systemError("Failed to initialize AVAudioPlayer: \(error.localizedDescription)")
            logger.error("Failed to initialize AVAudioPlayer: \(error)")
            reportError(err)
            return .failure(err)
        }
    }

    /// Prepare a mono preview file by downloading a remote WAV and downmixing all channels to mono.
    /// The resulting mono WAV is written to the Caches directory using the provided cacheKey and can be reused later.
    func prepareMonoPreview(for remoteURL: URL, cacheKey: String) async -> Result<URL, AudioError> {
        do {
            // 1) Download to a system-provided temporary file
            let (downloadedTempURL, _) = try await URLSession.shared.download(from: remoteURL)

            // 2) Destination in Caches (reusable across launches)
            let cachesDir = try FileManager.default.url(
                for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true
            )
            let baseName = (cacheKey as NSString).deletingPathExtension
            let monoURL = cachesDir
                .appendingPathComponent("mono-preview-\(baseName)")
                .appendingPathExtension("wav")

            // If already exists, reuse it
            if FileManager.default.fileExists(atPath: monoURL.path) {
                logger.debug("Using cached mono preview at \(monoURL.path)")
                return .success(monoURL)
            }

            // 3) Move the downloaded file to a stable location we control (URLSession may delete its temp file)
            let srcExt = (cacheKey as NSString).pathExtension.isEmpty ? (urlRequestExtension(from: remoteURL) ?? "wav") : (cacheKey as NSString).pathExtension
            let stableSrcURL = cachesDir
                .appendingPathComponent("mono-src-\(UUID().uuidString)")
                .appendingPathExtension(srcExt)

            do {
                // Move the downloaded temp file to our stable source URL
                try FileManager.default.moveItem(at: downloadedTempURL, to: stableSrcURL)
            } catch {
                logger.error("Failed to move downloaded file to stable location: \(error.localizedDescription)")
                throw error
            }

            // Prepare destination temp URL for atomic write
            let tmpURL = cachesDir
                .appendingPathComponent("mono-preview-\(baseName)-tmp")
                .appendingPathExtension("wav")

            // Log source/dest paths and sizes
            if let attrs = try? FileManager.default.attributesOfItem(atPath: stableSrcURL.path), let srcSize = attrs[.size] as? NSNumber {
                logger.debug("Downmix source: \(stableSrcURL.path) (\(srcSize.int64Value) bytes)")
            } else {
                logger.debug("Downmix source: \(stableSrcURL.path) (size unknown)")
            }
            logger.debug("Downmix dest tmp: \(tmpURL.path)")
            logger.debug("Final mono preview: \(monoURL.path)")

            #if os(iOS)
            var bgTask: UIBackgroundTaskIdentifier = .invalid
            bgTask = UIApplication.shared.beginBackgroundTask(withName: "DownmixMono") {
                UIApplication.shared.endBackgroundTask(bgTask)
                bgTask = .invalid
            }
            defer {
                if bgTask != .invalid {
                    UIApplication.shared.endBackgroundTask(bgTask)
                    bgTask = .invalid
                }
            }
            #endif

            do {
                let _ = try await Task.detached(priority: .utility) {
                    try AudioManager.downmixToMono(srcURL: stableSrcURL, dstURL: tmpURL)
                    return true
                }.value

                // Atomic move into place
                if FileManager.default.fileExists(atPath: monoURL.path) {
                    try? FileManager.default.removeItem(at: monoURL)
                }
                try FileManager.default.moveItem(at: tmpURL, to: monoURL)
            } catch {
                // Clean up any partial temp file
                try? FileManager.default.removeItem(at: tmpURL)
                // Also remove the stable source copy
                try? FileManager.default.removeItem(at: stableSrcURL)
                logger.error("Downmix failed: \(error.localizedDescription)")
                throw error
            }

            // Clean up the stable source file after successful conversion
            try? FileManager.default.removeItem(at: stableSrcURL)

            return .success(monoURL)
        } catch {
            let err: AudioError = .systemError("prepareMonoPreview failed: \(error.localizedDescription)")
            logger.error("prepareMonoPreview failed: \(error.localizedDescription)")
            reportError(err)
            return .failure(err)
        }
    }

    /// Extract a path extension from a URL if present, otherwise nil.
    private func urlRequestExtension(from url: URL) -> String? {
        let ext = url.pathExtension
        return ext.isEmpty ? nil : ext
    }

    /// Arm the preview playback by creating an AVAudioEngine graph and scheduling the file.
    /// Call `startArmedPreview(in:)` to begin playback at a precise time.
    func armPreviewPlayback(fileURL: URL) -> Result<String, AudioError> {
        do {
            // Stop any existing armed preview first
            stopArmedPreview()

            let engine = AVAudioEngine()
            let playerNode = AVAudioPlayerNode()
            engine.attach(playerNode)

            let file = try AVAudioFile(forReading: fileURL)
            self.previewFile = file
            let srcFormat = file.processingFormat

            engine.connect(playerNode, to: engine.mainMixerNode, format: srcFormat)

            try engine.start()

            // Schedule the file; actual start will be triggered via play(at:)
            playerNode.scheduleFile(file, at: nil, completionHandler: nil)

            self.previewEngine = engine
            self.previewPlayer = playerNode
            self.previewPlayer?.volume = volume

            return .success("Preview armed")
        } catch {
            let err: AudioError = .systemError("Failed to arm preview: \(error.localizedDescription)")
            logger.error("Failed to arm preview: \(error.localizedDescription)")
            reportError(err)
            return .failure(err)
        }
    }

    /// Start the previously armed preview at a precise time in the near future.
    /// Returns the host time used to start playback, which callers can use for synchronization.
    func startArmedPreview(in secondsFromNow: TimeInterval = 0.2) -> Result<UInt64, AudioError> {
        guard let player = self.previewPlayer else {
            let err: AudioError = .failedToLoad("No armed preview to start")
            reportError(err)
            return .failure(err)
        }

        let nowHost = mach_absolute_time()
        let deltaHost = AVAudioTime.hostTime(forSeconds: secondsFromNow)
        let startHost = nowHost &+ deltaHost

        player.play(at: AVAudioTime(hostTime: startHost))

        return .success(startHost)
    }

    /// Stop and tear down any armed preview engine/player.
    func stopArmedPreview() {
        if let player = self.previewPlayer {
            player.stop()
        }
        if let engine = self.previewEngine {
            engine.stop()
        }
        self.previewPlayer = nil
        self.previewEngine = nil
        self.previewFile = nil
    }

    /// Helper that performs a block-by-block downmix from any channel count to mono and writes a WAV file.
    /// This function is non-actor-isolated and safe to call from a detached task.
    nonisolated private static func downmixToMono(srcURL: URL, dstURL: URL) throws {
        let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "AudioManager.Downmix")
        guard FileManager.default.fileExists(atPath: srcURL.path) else {
            throw NSError(domain: "Audio", code: -12, userInfo: [NSLocalizedDescriptionKey: "Source file does not exist at path: \(srcURL.path)"])
        }

        // Open using ExtAudioFile for robust multi-channel WAV reading
        var extRef: ExtAudioFileRef?
        var status = ExtAudioFileOpenURL(srcURL as CFURL, &extRef)
        guard status == noErr, let extFile = extRef else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [NSLocalizedDescriptionKey: "ExtAudioFileOpenURL failed: \(status)"])
        }
        defer { ExtAudioFileDispose(extFile) }

        // Get the source file data format
        var fileASBD = AudioStreamBasicDescription()
        var propSize = UInt32(MemoryLayout.size(ofValue: fileASBD))
        status = ExtAudioFileGetProperty(extFile, kExtAudioFileProperty_FileDataFormat, &propSize, &fileASBD)
        guard status == noErr else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [NSLocalizedDescriptionKey: "ExtAudioFileGetProperty(FileDataFormat) failed: \(status)"])
        }

        let channels = Int(fileASBD.mChannelsPerFrame)
        let sampleRate = fileASBD.mSampleRate
        logger.debug("ExtAF file format: channels=\(channels), sampleRate=\(sampleRate, format: .fixed(precision: 0))")
        guard channels > 0 else {
            throw NSError(domain: "Audio", code: -10, userInfo: [NSLocalizedDescriptionKey: "Source file has zero channels"])
        }

        // Set client format to Float32, interleaved, same channel count (single buffer)
        var clientASBD = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4 * UInt32(channels),
            mFramesPerPacket: 1,
            mBytesPerFrame: 4 * UInt32(channels),
            mChannelsPerFrame: UInt32(channels),
            mBitsPerChannel: 32,
            mReserved: 0
        )
        propSize = UInt32(MemoryLayout.size(ofValue: clientASBD))
        status = ExtAudioFileSetProperty(extFile, kExtAudioFileProperty_ClientDataFormat, propSize, &clientASBD)
        guard status == noErr else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [NSLocalizedDescriptionKey: "ExtAudioFileSetProperty(ClientDataFormat) failed: \(status)"])
        }

        // Prepare destination writer (Float32 mono WAV)
        let dstSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false
        ]
        logger.debug("Creating destination mono WAV at \(dstURL.path)")
        if FileManager.default.fileExists(atPath: dstURL.path) {
            try? FileManager.default.removeItem(at: dstURL)
        }
        let dstFile: AVAudioFile
        do {
            dstFile = try AVAudioFile(forWriting: dstURL, settings: dstSettings)
        } catch {
            logger.error("Failed to create destination WAV at \(dstURL.path): \(error.localizedDescription)")
            throw NSError(domain: "Audio", code: -14, userInfo: [NSLocalizedDescriptionKey: "Failed to create destination WAV: \(error.localizedDescription)"])
        }

        guard let monoFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                             sampleRate: sampleRate,
                                             channels: 1,
                                             interleaved: false) else {
            throw NSError(domain: "Audio", code: -17, userInfo: [NSLocalizedDescriptionKey: "Failed to create mono float format"]) 
        }

        // Allocate a single interleaved float buffer for input
        let framesPerBlock: UInt32 = 16384
        let bytesPerFrame = Int(4 * channels) // float32 * channels (interleaved)
        let byteCapacity = Int(framesPerBlock) * bytesPerFrame
        let dataPtr = UnsafeMutableRawPointer.allocate(byteCount: byteCapacity, alignment: MemoryLayout<Float>.alignment)
        defer { dataPtr.deallocate() }

        var abl = AudioBufferList(
            mNumberBuffers: 1,
            mBuffers: AudioBuffer(mNumberChannels: UInt32(channels), mDataByteSize: 0, mData: nil)
        )

        while true {
            if Task.isCancelled { throw CancellationError() }

            var framesToRead: UInt32 = framesPerBlock
            abl.mBuffers.mNumberChannels = UInt32(channels)
            abl.mBuffers.mData = dataPtr
            abl.mBuffers.mDataByteSize = framesToRead * UInt32(bytesPerFrame)
            status = withUnsafeMutablePointer(to: &abl) { ptr in
                ExtAudioFileRead(extFile, &framesToRead, ptr)
            }
            if status != noErr {
                throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [NSLocalizedDescriptionKey: "ExtAudioFileRead failed: \(status)"])
            }
            if framesToRead == 0 { break }

            let outFrames = Int(framesToRead)
            let interleavedFloat = dataPtr.bindMemory(to: Float.self, capacity: outFrames * channels)

            // Downmix interleaved float -> mono
            guard let dstBuffer = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: AVAudioFrameCount(outFrames)),
                  let dstData = dstBuffer.floatChannelData else {
                throw NSError(domain: "Audio", code: -11, userInfo: [NSLocalizedDescriptionKey: "Buffer allocation/layout failed"]) 
            }
            dstBuffer.frameLength = AVAudioFrameCount(outFrames)
            let dst = dstData[0]
            vDSP_vclr(dst, 1, vDSP_Length(outFrames))

            let stride = vDSP_Stride(channels)
            for c in 0..<channels {
                vDSP_vadd(dst, 1, interleavedFloat.advanced(by: c), stride, dst, 1, vDSP_Length(outFrames))
            }
            var denom = Float(channels)
            vDSP_vsdiv(dst, 1, &denom, dst, 1, vDSP_Length(outFrames))

            do {
                try dstFile.write(from: dstBuffer)
            } catch let nsErr as NSError {
                logger.error("dstFile.write failed: domain=\(nsErr.domain) code=\(nsErr.code) desc=\(nsErr.localizedDescription)")
                throw nsErr
            }
        }
    }

    /// Remove stale or partial mono preview cache files.
    /// - Parameter maxAge: Files older than this age (in seconds) will be removed. Defaults to 7 days.
    nonisolated static func cleanupMonoPreviewCacheOnLaunch(maxAge: TimeInterval = 7 * 24 * 60 * 60) {
        let logger = Logger(subsystem: "io.opsnlops.CreatureConsole", category: "AudioManager.Cache")
        let fm = FileManager.default
        do {
            let cachesDir = try fm.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let urls = try fm.contentsOfDirectory(
                at: cachesDir,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
            let now = Date()
            var removedCount = 0

            for url in urls {
                let name = url.lastPathComponent
                guard name.hasPrefix("mono-preview-") else { continue }

                // Remove any leftover temporary files (e.g., mono-preview-*.wav.tmp)
                if url.pathExtension == "tmp" {
                    try? fm.removeItem(at: url)
                    removedCount += 1
                    continue
                }

                // Remove old cached previews beyond maxAge
                if name.hasSuffix(".wav") {
                    let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
                    if values?.isRegularFile == true,
                       let modDate = values?.contentModificationDate,
                       now.timeIntervalSince(modDate) > maxAge {
                        try? fm.removeItem(at: url)
                        removedCount += 1
                    }
                }
            }
            if removedCount > 0 {
                logger.info("Cleaned up \(removedCount) mono preview cache file(s)")
            }
        } catch {
            logger.warning("Failed to enumerate Caches for cleanup: \(error.localizedDescription)")
        }
    }

    func pause() {
        logger.info("pausing audio")
        self.audioPlayer?.pause()
        self.player?.pause()
    }

    deinit {
        NotificationCenter.default.removeObserver(self, name: UserDefaults.didChangeNotification, object: nil)
    }

    @objc private func userDefaultsDidChange(_ notification: Notification) {
        // Read as Double for consistency
        let newVal = UserDefaults.standard.object(forKey: "audioVolume") as? Double
        let newVolume = Float(newVal ?? Double(self.volume))
        if newVolume != self.volume {
            self.volume = newVolume
        }
    }
}

