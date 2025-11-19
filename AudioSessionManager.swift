import AVFAudio   // modern module that includes AVAudioSession

enum AudioSessionManager {
    static func configure() {
        let session = AVAudioSession.sharedInstance()
        do {
            // Ultra-simple, always-valid configuration:
            // - playback category
            // - default mode
            // - no extra options
            try session.setCategory(.playback, mode: .spokenAudio, options: [])
            try session.setActive(true)

            print("Audio session configured for background playback")
            print("DEBUG: AVAudioSession category = \(session.category.rawValue)")
        } catch {
            print("Audio session ERROR: \(error)")
        }
    }
}

