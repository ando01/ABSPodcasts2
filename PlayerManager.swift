import Foundation
import AVFoundation
import MediaPlayer
import UIKit
import Combine

/// Central playback manager for podcasts + audiobooks.
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

    /// Cached artwork image used for lockscreen / CarPlay
    private var artworkImage: UIImage?

    // MARK: - Public API

    func start(episode: ABSClient.Episode, audioURL: URL, artworkURL: URL?) {
        print("▶️ [PlayerManager] start() id=\(episode.id)")

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

        // Prefer local downloaded copy if available
        let finalURL: URL
        if let local = DownloadManager.shared.localURL(for: episode.id) {
            finalURL = local
            print("📀 [PlayerManager] Using LOCAL audio at \(local.path)")
        } else {
            finalURL = audioURL
            print("🌐 [PlayerManager] Using REMOTE audio at \(audioURL)")
        }

        let item = AVPlayerItem(url: finalURL)
        let player = AVPlayer(playerItem: item)
        self.player = player

        // Remember last played item
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

        // Load artwork (from cache first, then network)
        loadArtworkForNowPlaying()

        // Start playback
        play()
        updateNowPlayingInfo()
    }

    func play() {
        guard let player = player else { return }
        player.playImmediately(atRate: Float(playbackSpeed))
        isPlaying = true
        print("▶️ [PlayerManager] play()")
        updateNowPlayingInfo()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        print("⏸ [PlayerManager] pause()")
        updateNowPlayingInfo()
    }

    func togglePlayPause() {
        isPlaying ? pause() : play()
    }

    func seek(to time: Double) {
        guard let player = player else { return }
        let clamped = max(time, 0)
        let cmTime = CMTime(seconds: clamped, preferredTimescale: 600)
        player.seek(to: cmTime) { [weak self] _ in
            guard let self else { return }
            self.currentTime = clamped
            print("⏩ [PlayerManager] seek(to: \(clamped))")
            self.updateNowPlayingInfo()
        }
    }

    func skip(by seconds: Double) {
        seek(to: currentTime + seconds)
    }

    func setSpeed(_ speed: Double) {
        playbackSpeed = speed
        if isPlaying {
            player?.rate = Float(speed)
        }
        print("🎚 [PlayerManager] setSpeed(\(speed))")
        updateNowPlayingInfo()
    }

    func stop() {
        print("⏹ [PlayerManager] stop()")
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

    private func loadDuration() {
        guard let player = player,
              let item = player.currentItem else { return }

        let asset = item.asset

        Task {
            do {
                let time = try await asset.load(.duration)
                let durationSeconds = time.seconds
                guard durationSeconds.isFinite else { return }

                await MainActor.run {
                    self.duration = durationSeconds
                    print("⏱ [PlayerManager] duration=\(durationSeconds)")
                    self.updateNowPlayingInfo()
                }
            } catch {
                print("⚠️ [PlayerManager] Failed to load duration: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Artwork loading for lockscreen / CarPlay

    private func loadArtworkForNowPlaying() {
        guard let episode = currentEpisode else { return }

        // 1) Cached artwork on disk?
        if let cached = DownloadManager.shared.cachedArtworkImage(for: episode.id) {
            print("🎨 [PlayerManager] Using CACHED artwork for id=\(episode.id)")
            self.artworkImage = cached
            self.updateNowPlayingInfo()
            return
        } else {
            print("🎨 [PlayerManager] No cached artwork for id=\(episode.id), will try remote")
        }

        // 2) Fallback to remote artworkURL (only works when online)
        guard let url = artworkURL else {
            print("🎨 [PlayerManager] No artworkURL available for id=\(episode.id)")
            return
        }

        Task.detached { [weak self] in
            guard let self else { return }

            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                guard let image = UIImage(data: data) else {
                    print("⚠️ [PlayerManager] Could not decode remote artwork image")
                    return
                }

                await MainActor.run {
                    print("🎨 [PlayerManager] Loaded REMOTE artwork for id=\(episode.id)")
                    self.artworkImage = image
                    self.updateNowPlayingInfo()
                }

                // Cache for offline playback
                await DownloadManager.shared.storeArtwork(id: episode.id, from: url)
            } catch {
                print("⚠️ [PlayerManager] Failed to load remote artwork: \(error)")
            }
        }
    }

    // MARK: - Remote commands

    private func setupRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()

        // Clear previous
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

        if let img = artworkImage {
            let artwork = MPMediaItemArtwork(boundsSize: img.size) { _ in img }
            info[MPMediaItemPropertyArtwork] = artwork
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}

