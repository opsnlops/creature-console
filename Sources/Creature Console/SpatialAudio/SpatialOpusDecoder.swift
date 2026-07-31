#if os(macOS)
    import Common
    import Foundation
    import YbridOpus

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

    enum SpatialOpusDecoderError: LocalizedError {
        case creationFailed(code: Int32)

        var errorDescription: String? {
            switch self {
            case .creationFailed(let code):
                "Unable to create an Opus decoder (error \(code))."
            }
        }
    }
#endif
