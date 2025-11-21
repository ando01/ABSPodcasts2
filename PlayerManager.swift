import Foundation
import AVFoundation
import MediaPlayer
import Combine

final class PlayerManager: ObservableObject {

    // MARK: - Published state for the UI

    @Published var currentEpisode: ABSClient.Episode?
    @Published var artworkURL: URL?

    /// Whether the full-screen Now Playing sheet is showing.
    @Published var isPresented: Bool = false

    /// True while AVPlayer is actually playing.
    @Published var isPlaying: Bool = false

    /// Current playback time and duration (in seconds).
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0

    /// Current playback speed (1.0 = normal).
    @Published var playbackSpeed: Float = 1.0

    /// Show mini player when an episode is active.
    var isActive: Bool {
        currentEpisode != nil
    }

    // MARK: - Private

    private var player: AVPlayer?
    private var timeObserverToken: Any?
    private let progressManager = PlaybackProgressManager.shared
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Public API

    /// Start playing an episode.
    func start(episode: ABSClient.Episode, audioURL: URL, artworkURL: URL?) {
        cleanupPlayer()

        currentEpisode = episode
        self.artworkURL = artworkURL
        currentTime = 0
        duration = 0
        isPlaying = false

        let player = AVPlayer(url: audioURL)
        self.player = player

        setupPeriodicTimeObserver()
        loadDuration()
        setupRemoteCommands()

        // default speed if not already set
        if playbackSpeed <= 0 {
            playbackSpeed = 1.0
        }

        play()
        isPresented = true
    }

    /// Show the full-screen Now Playing sheet.
    func present() {
        if isActive {
            isPresented = true
        }
    }

    /// Hide the sheet but keep audio playing.
    func minimize() {
        isPresented = false
    }

    /// Stop playback completely and clear state.
    func stop() {
        pause()
        currentEpisode = nil
        artworkURL = nil
        cleanupPlayer()
        isPresented = false
    }

    func play() {
        guard let player else { return }
        player.play()
        player.rate = playbackSpeed
        isPlaying = true
        updateNowPlayingInfo()
    }

    func pause() {
        guard let player else { return }
        player.pause()
        isPlaying = false
        saveProgress()
        updateNowPlayingInfo()
    }

    func togglePlayPause() {
        isPlaying ? pause() : play()
    }

    func seek(to seconds: Double) {
        guard let player else { return }
        let clamped = max(0, min(seconds, duration > 0 ? duration : seconds))
        let cm = CMTime(seconds: clamped, preferredTimescale: 600)
        player.seek(to: cm) { [weak self] _ in
            self?.currentTime = clamped
            self?.updateNowPlayingInfo()
        }
    }

    func skip(by delta: Double) {
        seek(to: currentTime + delta)
    }

    func setSpeed(_ speed: Float) {
        playbackSpeed = speed
        if isPlaying {
            player?.rate = speed
        }
        updateNowPlayingInfo()
    }

    // MARK: - Private helpers

    private func setupPeriodicTimeObserver() {
        guard let player else { return }

        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            guard let self else { return }
            self.currentTime = time.seconds
            self.updateNowPlayingInfo()

            // Save progress every ~5 seconds
            if Int(self.currentTime) % 5 == 0 {
                self.saveProgress()
            }
        }
    }

    private func loadDuration() {
        guard let item = player?.currentItem else { return }
        let asset = item.asset

        Task {
            do {
                let cmDuration = try await asset.load(.duration)
                let secs = cmDuration.seconds
                if secs.isFinite && secs > 0 {
                    await MainActor.run {
                        self.duration = secs
                        self.updateNowPlayingInfo()
                    }
                }
            } catch {
                print("⚠️ Failed to load duration: \(error)")
            }
        }
    }

    private func cleanupPlayer() {
        if let player, let token = timeObserverToken {
            player.removeTimeObserver(token)
        }
        timeObserverToken = nil
        player = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: - Progress

    private func saveProgress() {
        guard let episodeId = currentEpisode?.id, duration > 0 else { return }
        progressManager.saveProgress(
            episodeId: episodeId,
            currentTime: currentTime,
            duration: duration
        )
    }

    // MARK: - Remote commands + Now Playing

    private func setupRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()

        // Clear old targets if you want to be super safe (optional, but avoids duplicates)
        commandCenter.playCommand.removeTarget(nil)
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.togglePlayPauseCommand.removeTarget(nil)
        commandCenter.skipBackwardCommand.removeTarget(nil)
        commandCenter.skipForwardCommand.removeTarget(nil)
        commandCenter.nextTrackCommand.removeTarget(nil)
        commandCenter.previousTrackCommand.removeTarget(nil)
        commandCenter.seekForwardCommand.removeTarget(nil)
        commandCenter.seekBackwardCommand.removeTarget(nil)

        // Play
        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.play()
            return .success
        }

        // Pause
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }

        // Toggle
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.togglePlayPause()
            return .success
        }

        // Base skip amounts (you can tweak these)
        let backwardSeconds: Double = 15
        let forwardSeconds: Double = 30

        // Skip backward (e.g. from Control Center skip back button)
        commandCenter.skipBackwardCommand.isEnabled = true
        commandCenter.skipBackwardCommand.preferredIntervals = [NSNumber(value: backwardSeconds)]
        commandCenter.skipBackwardCommand.addTarget { [weak self] _ in
            self?.skip(by: -backwardSeconds)
            return .success
        }

        // Skip forward (e.g. from Control Center)
        commandCenter.skipForwardCommand.isEnabled = true
        commandCenter.skipForwardCommand.preferredIntervals = [NSNumber(value: forwardSeconds)]
        commandCenter.skipForwardCommand.addTarget { [weak self] _ in
            self?.skip(by: forwardSeconds)
            return .success
        }

        // 🎧 AirPods often send these as "next/previous track"
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            self?.skip(by: forwardSeconds)
            return .success
        }

        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            self?.skip(by: -backwardSeconds)
            return .success
        }

        // Some devices use continuous seeking – we map these to discrete skips too
        commandCenter.seekForwardCommand.isEnabled = true
        commandCenter.seekForwardCommand.addTarget { [weak self] event in
            guard let self,
                  let seekEvent = event as? MPSeekCommandEvent
            else { return .commandFailed }

            if seekEvent.type == .beginSeeking {
                // Treat as a small skip when user initiates
                self.skip(by: forwardSeconds)
            }
            return .success
        }

        commandCenter.seekBackwardCommand.isEnabled = true
        commandCenter.seekBackwardCommand.addTarget { [weak self] event in
            guard let self,
                  let seekEvent = event as? MPSeekCommandEvent
            else { return .commandFailed }

            if seekEvent.type == .beginSeeking {
                self.skip(by: -backwardSeconds)
            }
            return .success
        }
    }


    private func updateNowPlayingInfo() {
        guard let episode = currentEpisode else { return }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: episode.title,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? playbackSpeed : 0.0,
            MPMediaItemPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue
        ]

        if duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

}

