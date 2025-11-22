import Foundation
import AVFoundation
import MediaPlayer
import UIKit
import Combine

/// Central playback manager for podcasts + audiobooks.
/// Owns the AVPlayer and publishes state to the UI (mini player, NowPlayingView, etc.)
final class PlayerManager: ObservableObject {

    // MARK: - Published state for UI

    @Published var currentEpisode: ABSClient.Episode?
    @Published var audioURL: URL?
    @Published var artworkURL: URL?

    @Published var isPlaying: Bool = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0

    /// Whether something is loaded (used to show/hide mini-player)
    @Published var isActive: Bool = false

    /// Controls whether full-screen Now Playing sheet is shown
    @Published var isPresented: Bool = false

    /// Playback speed (e.g. 1.0, 1.25, 1.5, 2.0)
    @Published var playbackSpeed: Double = 1.0

    // MARK: - Private

    private var player: AVPlayer?
    private var timeObserver: Any?

    private let progressManager = PlaybackProgressManager.shared

    /// Cached artwork image used for lockscreen / CarPlay / Watch
    private var artworkImage: UIImage?

    // MARK: - Public API

    /// Start playback of an episode (podcast or audiobook).
    /// - Parameters:
    ///   - episode: ABSClient.Episode (can be a "fake" one for audiobooks)
    ///   - audioURL: Direct stream URL
    ///   - artworkURL: Cover art URL (what you also use in SwiftUI)
    func start(episode: ABSClient.Episode, audioURL: URL, artworkURL: URL?) {
        // Clean up any existing player
        cleanupPlayer()

        currentEpisode = episode
        self.audioURL = audioURL
        self.artworkURL = artworkURL

        currentTime = 0
        duration = 0
        isPlaying = false
        isActive = true
        isPresented = true
        playbackSpeed = max(playbackSpeed, 1.0)
        artworkImage = nil

        // Create new player instance
        let player = AVPlayer(url: audioURL)
        self.player = player

        // Remember last played item for "Pick up where you left off"
        progressManager.saveLastPlayed(
            episodeId: episode.id,
            title: episode.title,
            streamURLString: audioURL.absoluteString,
            artworkURLString: artworkURL?.absoluteString
        )

        // Observe time / duration, remote commands, etc.
        setupPeriodicTimeObserver()
        loadDuration()
        setupRemoteCommands()

        // Load artwork for lock screen / CarPlay
        loadArtworkForNowPlaying()

        // Start playback
        play()
        updateNowPlayingInfo()
    }

    /// Play current item
    func play() {
        guard let player = player else { return }
        player.playImmediately(atRate: Float(playbackSpeed))
        isPlaying = true
        updateNowPlayingInfo()
    }

    /// Pause current item
    func pause() {
        player?.pause()
        isPlaying = false
        updateNowPlayingInfo()
    }

    /// Toggle between play and pause
    func togglePlayPause() {
        isPlaying ? pause() : play()
    }

    /// Seek to an absolute time in seconds
    func seek(to time: Double) {
        guard let player = player else { return }
        let clamped = max(time, 0)
        let cmTime = CMTime(seconds: clamped, preferredTimescale: 600)
        player.seek(to: cmTime) { [weak self] _ in
            guard let self else { return }
            self.currentTime = clamped
            self.updateNowPlayingInfo()
        }
    }

    /// Skip forward or backward by a delta in seconds
    func skip(by seconds: Double) {
        seek(to: currentTime + seconds)
    }

    /// Change playback speed
    func setSpeed(_ speed: Double) {
        playbackSpeed = speed
        if isPlaying {
            player?.rate = Float(speed)
        }
        updateNowPlayingInfo()
    }

    /// Stop playback and clear state
    func stop() {
        cleanupPlayer()

        currentEpisode = nil
        audioURL = nil
        artworkURL = nil
        artworkImage = nil

        currentTime = 0
        duration = 0
        isPlaying = false
        isActive = false
        isPresented = false

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: - Private helpers

    private func cleanupPlayer() {
        if let token = timeObserver {
            player?.removeTimeObserver(token)
            timeObserver = nil
        }
        player?.pause()
        player = nil
    }

    // Periodically update current time + save progress + update Now Playing
    private func setupPeriodicTimeObserver() {
        guard let player = player else { return }

        let interval = CMTime(seconds: 1, preferredTimescale: 2)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) {
            [weak self] time in
            guard let self else { return }
            let seconds = time.seconds
            guard seconds.isFinite else { return }

            self.currentTime = seconds
            self.updateNowPlayingInfo()

            if let episode = self.currentEpisode {
                self.progressManager.saveProgress(
                    episodeId: episode.id,
                    currentTime: seconds,
                    duration: self.duration
                )
            }
        }
    }

    // Load total duration once AVAsset loads
    private func loadDuration() {
        guard let player = player,
              let item = player.currentItem else { return }

        let asset = item.asset

        Task {
            do {
                // New async API in iOS 15+ / 16+
                let time = try await asset.load(.duration)
                let durationSeconds = time.seconds
                guard durationSeconds.isFinite else { return }

                await MainActor.run {
                    self.duration = durationSeconds
                    self.updateNowPlayingInfo()
                }
            } catch {
                // Optional: log, but don't crash playback if duration fails
                print("⚠️ Failed to load duration: \(error.localizedDescription)")
            }
        }
    }


    // MARK: - Artwork loading for lockscreen / CarPlay

    /// Fetch cover image from artworkURL and cache it as UIImage
    private func loadArtworkForNowPlaying() {
        guard let url = artworkURL else { return }

        // Do not block the main thread
        Task.detached { [weak self] in
            guard let self else { return }

            if let data = try? Data(contentsOf: url),
               let image = UIImage(data: data) {
                await MainActor.run {
                    self.artworkImage = image
                    self.updateNowPlayingInfo()
                }
            }
        }
    }

    // MARK: - Remote command center

    private func setupRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()

        // Remove any previous targets
        commandCenter.playCommand.removeTarget(nil)
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.togglePlayPauseCommand.removeTarget(nil)
        commandCenter.skipBackwardCommand.removeTarget(nil)
        commandCenter.skipForwardCommand.removeTarget(nil)
        commandCenter.nextTrackCommand.removeTarget(nil)
        commandCenter.previousTrackCommand.removeTarget(nil)
        commandCenter.seekForwardCommand.removeTarget(nil)
        commandCenter.seekBackwardCommand.removeTarget(nil)

        let backwardSeconds: Double = 15
        let forwardSeconds: Double = 30

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

        // Skip backward
        commandCenter.skipBackwardCommand.isEnabled = true
        commandCenter.skipBackwardCommand.preferredIntervals = [NSNumber(value: backwardSeconds)]
        commandCenter.skipBackwardCommand.addTarget { [weak self] _ in
            self?.skip(by: -backwardSeconds)
            return .success
        }

        // Skip forward
        commandCenter.skipForwardCommand.isEnabled = true
        commandCenter.skipForwardCommand.preferredIntervals = [NSNumber(value: forwardSeconds)]
        commandCenter.skipForwardCommand.addTarget { [weak self] _ in
            self?.skip(by: forwardSeconds)
            return .success
        }

        // Map next/previous to skips (AirPods, CarPlay)
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

        // Optional: treat seek commands as discrete skips too
        commandCenter.seekForwardCommand.isEnabled = true
        commandCenter.seekForwardCommand.addTarget { [weak self] event in
            guard let self,
                  let seekEvent = event as? MPSeekCommandEvent else {
                return .commandFailed
            }
            if seekEvent.type == .beginSeeking {
                self.skip(by: forwardSeconds)
            }
            return .success
        }

        commandCenter.seekBackwardCommand.isEnabled = true
        commandCenter.seekBackwardCommand.addTarget { [weak self] event in
            guard let self,
                  let seekEvent = event as? MPSeekCommandEvent else {
                return .commandFailed
            }
            if seekEvent.type == .beginSeeking {
                self.skip(by: -backwardSeconds)
            }
            return .success
        }
    }

    // MARK: - Now Playing Info (lockscreen / CarPlay / Watch)

    private func updateNowPlayingInfo() {
        guard let episode = currentEpisode else { return }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: episode.title,
            MPMediaItemPropertyArtist: "Audiobookshelf",
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? playbackSpeed : 0.0,
            MPMediaItemPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue
        ]

        if duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }

        // Attach artwork if loaded
        if let img = artworkImage {
            let artwork = MPMediaItemArtwork(boundsSize: img.size) { _ in img }
            info[MPMediaItemPropertyArtwork] = artwork
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}

