#if os(iOS) || os(tvOS)
    import AVFAudio

    /// iOS and tvOS route audio through AVAudioSession (macOS has none). Configure playback
    /// before constructing AVAudioEngine so its environment node sees the final output route.
    enum SpatialAudioSession {
        static func configureForPlayback() throws {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            #if os(tvOS)
                // The TV wants as many discrete HDMI channels as the route offers (up to 7.1).
                // On a stereo route this quietly stays at two channels.
                let channelCount = min(session.maximumOutputNumberOfChannels, 8)
                try session.setPreferredOutputNumberOfChannels(channelCount)
            #endif
        }
    }
#endif
