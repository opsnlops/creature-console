import AVFoundation
import Foundation

/// Peak envelope of an audio file, for drawing. `peaks` are 0…1, one per bin across the whole
/// file, normalised so the loudest bin is 1.
struct MusicWaveform: Equatable, Sendable {
    let peaks: [Float]
    let duration: TimeInterval

    static let empty = MusicWaveform(peaks: [], duration: 0)

    /// Decodes `url` (any format AVAudioFile reads, including MP3) into `bins` peak values.
    /// Runs off the main actor; a 10-minute file is a few hundred milliseconds of work.
    static func decode(url: URL, bins: Int = 800) async throws -> MusicWaveform {
        try await Task.detached(priority: .userInitiated) {
            try decodeSync(url: url, bins: bins)
        }.value
    }

    private static func decodeSync(url: URL, bins: Int) throws -> MusicWaveform {
        let file = try AVAudioFile(
            forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        let format = file.processingFormat
        let totalFrames = Int(file.length)
        guard totalFrames > 0, bins > 0 else { return .empty }
        let duration = Double(totalFrames) / format.sampleRate
        let framesPerBin = max(1, totalFrames / bins)
        var peaks = [Float](repeating: 0, count: bins)

        let blockFrames: AVAudioFrameCount = 16_384
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: blockFrames)
        else { return .empty }
        var frameCursor = 0
        while frameCursor < totalFrames {
            try file.read(into: buffer, frameCount: blockFrames)
            let frames = Int(buffer.frameLength)
            if frames == 0 { break }
            guard let channels = buffer.floatChannelData else { break }
            let channelCount = Int(format.channelCount)
            for frame in 0..<frames {
                var magnitude: Float = 0
                for channel in 0..<channelCount {
                    magnitude = max(magnitude, abs(channels[channel][frame]))
                }
                let bin = min(bins - 1, (frameCursor + frame) / framesPerBin)
                if magnitude > peaks[bin] { peaks[bin] = magnitude }
            }
            frameCursor += frames
        }

        if let loudest = peaks.max(), loudest > 0 {
            peaks = peaks.map { $0 / loudest }
        }
        return MusicWaveform(peaks: peaks, duration: duration)
    }
}
