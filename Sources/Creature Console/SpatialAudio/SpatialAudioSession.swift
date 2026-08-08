#if os(tvOS)
    import AVFAudio

    /// tvOS routes audio through AVAudioSession (macOS has none). Every spatial playback path
    /// on the TV — audition and live monitoring alike — wants the same thing: as many discrete
    /// output channels as the HDMI route offers (up to 7.1), negotiated *before* the engine
    /// spins up, so the environment node renders to the real layout instead of a stereo
    /// fold-down. On a stereo route this quietly stays 2ch.
    enum SpatialAudioSession {
        static func configureForMultichannelPlayback() throws {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            let channelCount = min(session.maximumOutputNumberOfChannels, 8)
            try session.setPreferredOutputNumberOfChannels(channelCount)
        }
    }
#endif
