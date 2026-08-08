#if os(macOS) || os(tvOS)
    import Common
    import Foundation

    enum SpatialOpusDecoderError: LocalizedError {
        case creationFailed(code: Int32)

        var errorDescription: String? {
            switch self {
            case .creationFailed(let code):
                "Unable to create an Opus decoder (error \(code))."
            }
        }
    }

    #if os(macOS)
        import YbridOpus

        /// libopus-backed decoder: full fidelity including forward error correction and packet
        /// loss concealment, which matter on the lossy multicast transport.
        final class SpatialOpusDecoder: @unchecked Sendable {
            enum DecodeKind: Sendable {
                case packet
                case forwardErrorCorrection
                case packetLossConcealment
                case silence
            }

            private var decoder: OpaquePointer?

            init() throws {
                try createDecoder()
            }

            deinit {
                if let decoder {
                    opus_decoder_destroy(decoder)
                }
            }

            func reset() throws {
                if let decoder {
                    opus_decoder_destroy(decoder)
                }
                decoder = nil
                try createDecoder()
            }

            func decode(
                payload: Data?,
                forwardErrorCorrectionPayload: Data?
            ) -> (samples: [Float], kind: DecodeKind) {
                guard let decoder else {
                    return (Self.silence, .silence)
                }

                var samples = Self.silence
                let result: Int32
                let kind: DecodeKind

                if let payload {
                    result = payload.withUnsafeBytes { bytes in
                        opus_decode_float(
                            decoder,
                            bytes.bindMemory(to: UInt8.self).baseAddress,
                            Int32(payload.count),
                            &samples,
                            Int32(RTPAudioConstants.framesPerPacket),
                            0
                        )
                    }
                    kind = .packet
                } else if let forwardErrorCorrectionPayload {
                    result = forwardErrorCorrectionPayload.withUnsafeBytes { bytes in
                        opus_decode_float(
                            decoder,
                            bytes.bindMemory(to: UInt8.self).baseAddress,
                            Int32(forwardErrorCorrectionPayload.count),
                            &samples,
                            Int32(RTPAudioConstants.framesPerPacket),
                            1
                        )
                    }
                    kind = .forwardErrorCorrection
                } else {
                    result = opus_decode_float(
                        decoder,
                        nil,
                        0,
                        &samples,
                        Int32(RTPAudioConstants.framesPerPacket),
                        0
                    )
                    kind = .packetLossConcealment
                }

                guard result > 0 else {
                    return (Self.silence, .silence)
                }
                if result < Int32(samples.count) {
                    samples.replaceSubrange(
                        Int(result)..<samples.count,
                        with: repeatElement(0, count: samples.count - Int(result)))
                }
                return (samples, kind)
            }

            private func createDecoder() throws {
                var error: Int32 = OPUS_OK
                decoder = opus_decoder_create(
                    opus_int32(RTPAudioConstants.sampleRate),
                    1,
                    &error
                )
                guard decoder != nil, error == OPUS_OK else {
                    throw SpatialOpusDecoderError.creationFailed(code: error)
                }
            }

            private static let silence = [Float](
                repeating: 0,
                count: Int(RTPAudioConstants.framesPerPacket)
            )
        }

    #elseif os(tvOS)
        import AVFAudio

        /// AVAudioConverter-backed decoder (`kAudioFormatOpus`): YbridOpus ships no tvOS slice,
        /// so the TV decodes with the system codec instead. It has no FEC or PLC — acceptable,
        /// because the only transport that reaches tvOS is the TCP relay, where packets are
        /// never lost, only late; a stall fills with silence.
        final class SpatialOpusDecoder: @unchecked Sendable {
            enum DecodeKind: Sendable {
                case packet
                case forwardErrorCorrection
                case packetLossConcealment
                case silence
            }

            private let inputFormat: AVAudioFormat
            private let outputFormat: AVAudioFormat
            private var converter: AVAudioConverter

            init() throws {
                var streamDescription = AudioStreamBasicDescription(
                    mSampleRate: Float64(RTPAudioConstants.sampleRate),
                    mFormatID: kAudioFormatOpus,
                    mFormatFlags: 0,
                    mBytesPerPacket: 0,
                    mFramesPerPacket: RTPAudioConstants.framesPerPacket,
                    mBytesPerFrame: 0,
                    mChannelsPerFrame: 1,
                    mBitsPerChannel: 0,
                    mReserved: 0
                )
                guard
                    let input = AVAudioFormat(streamDescription: &streamDescription),
                    let output = AVAudioFormat(
                        commonFormat: .pcmFormatFloat32,
                        sampleRate: Double(RTPAudioConstants.sampleRate),
                        channels: 1,
                        interleaved: false
                    ),
                    let converter = AVAudioConverter(from: input, to: output)
                else {
                    throw SpatialOpusDecoderError.creationFailed(code: -1)
                }
                self.inputFormat = input
                self.outputFormat = output
                self.converter = converter
            }

            func reset() throws {
                // New synchronization source — drop any codec history.
                converter.reset()
            }

            func decode(
                payload: Data?,
                forwardErrorCorrectionPayload: Data?
            ) -> (samples: [Float], kind: DecodeKind) {
                // No FEC or PLC without libopus: only a real packet produces audio.
                guard let payload, !payload.isEmpty else {
                    return (Self.silence, .silence)
                }

                let compressed = AVAudioCompressedBuffer(
                    format: inputFormat,
                    packetCapacity: 1,
                    maximumPacketSize: RTPAudioConstants.maximumPacketSize
                )
                payload.withUnsafeBytes { bytes in
                    compressed.data.copyMemory(
                        from: bytes.baseAddress!, byteCount: payload.count)
                }
                compressed.byteLength = UInt32(payload.count)
                compressed.packetCount = 1
                compressed.packetDescriptions?.pointee = AudioStreamPacketDescription(
                    mStartOffset: 0,
                    mVariableFramesInPacket: 0,
                    mDataByteSize: UInt32(payload.count)
                )

                guard
                    let pcm = AVAudioPCMBuffer(
                        pcmFormat: outputFormat,
                        frameCapacity: AVAudioFrameCount(RTPAudioConstants.framesPerPacket)
                    )
                else {
                    return (Self.silence, .silence)
                }

                var fed = false
                var conversionError: NSError?
                let status = converter.convert(to: pcm, error: &conversionError) {
                    _, outStatus in
                    if fed {
                        outStatus.pointee = .noDataNow
                        return nil
                    }
                    fed = true
                    outStatus.pointee = .haveData
                    return compressed
                }

                guard status != .error, conversionError == nil, pcm.frameLength > 0,
                    let channelData = pcm.floatChannelData
                else {
                    return (Self.silence, .silence)
                }

                var samples = Self.silence
                let produced = min(Int(pcm.frameLength), samples.count)
                samples.withUnsafeMutableBufferPointer { buffer in
                    buffer.baseAddress!.update(from: channelData[0], count: produced)
                }
                return (samples, .packet)
            }

            private static let silence = [Float](
                repeating: 0,
                count: Int(RTPAudioConstants.framesPerPacket)
            )
        }
    #endif
#endif
