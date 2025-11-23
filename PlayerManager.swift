import Foundation
import AVFoundation
import MediaPlayer
import SwiftUI
import Combine
import UIKit

// MARK: - Types from your API layer

/// Your Episode model from ABSClient
typealias Episode = ABSClient.Episode
typealias LibraryItem = ABSClient.LibraryItem

// MARK: - Chapter model

struct Chapter: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let startTime: TimeInterval
}

// MARK: - Progress storage

/// Abstraction so you can swap in a different backend if desired.
protocol EpisodeProgressStoring {
    func saveProgress(
        serverKey: String,
        libraryItemId: String,
        episodeId: String,
        time: TimeInterval,
        duration: TimeInterval
    )

    func loadProgress(
        serverKey: String,
        libraryItemId: String,
        episodeId: String
    ) -> (time: TimeInterval, duration: TimeInterval)?
}

/// Default implementation using UserDefaults
final class UserDefaultsEpisodeProgressStore: EpisodeProgressStoring {
    private let defaults: UserDefaults
    private let keyPrefix = "EpisodeProgress"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private func key(serverKey: String, libraryItemId: String, episodeId: String) -> String {
        "\(keyPrefix)|\(serverKey)|\(libraryItemId)|\(episodeId)"
    }

    func saveProgress(
        serverKey: String,
        libraryItemId: String,
        episodeId: String,
        time: TimeInterval,
        duration: TimeInterval
    ) {
        let k = key(serverKey: serverKey, libraryItemId: libraryItemId, episodeId: episodeId)
        let dict: [String: Any] = ["time": time, "duration": duration]
        defaults.set(dict, forKey: k)
    }

    func loadProgress(
        serverKey: String,
        libraryItemId: String,
        episodeId: String
    ) -> (time: TimeInterval, duration: TimeInterval)? {
        let k = key(serverKey: serverKey, libraryItemId: libraryItemId, episodeId: episodeId)
        guard let dict = defaults.dictionary(forKey: k),
              let time = dict["time"] as? TimeInterval,
              let duration = dict["duration"] as? TimeInterval
        else { return nil }
        return (time, duration)
    }
}

// MARK: - PlayerManager

/// Central playback controller shared across the app.
/// Inject once at the top-level and then use as an EnvironmentObject.
final class PlayerManager: ObservableObject {

    // MARK: - Published state for SwiftUI

    /// Currently loaded library item (podcast / show).
    @Published private(set) var currentLibraryItem: LibraryItem?

    /// Currently loaded episode.
    @Published private(set) var currentEpisode: Episode?

    /// Stream/file URL for currently loaded episode.
    @Published private(set) var audioURL: URL?

    /// Resolved artwork URL (Audiobookshelf cover).
    @Published private(set) var artworkURL: URL?

    /// Controls presentation of the full-screen Now Playing sheet.
    @Published var isPresented: Bool = false

    /// Is the player currently playing?
    @Published private(set) var isPlaying: Bool = false

    /// Current playback position (seconds).
    @Published private(set) var currentTime: TimeInterval = 0

    /// Duration of the current item (seconds).
    @Published private(set) var duration: TimeInterval = 0

    /// Playback rate (1.0 = normal).
    @Published var playbackRate: Float = 1.0 {
        didSet {
            player.rate = isPlaying ? playbackRate : 0
            updateNowPlayingInfo()
            
        }
    }

    /// Detected chapters for the current episode (if any).
    @Published private(set) var chapters: [Chapter] = []

    /// Index of the currently active chapter based on `currentTime`.
    @Published private(set) var currentChapterIndex: Int?
    
    // MARK: - Library context for Home screen

    /// All libraries the user can access (for the home screen picker).
    @Published var availableLibraries: [ABSClient.Library] = []


    // MARK: - Server context

    /// Set this when you create the manager, e.g. from your ABSClient.
    var serverURL: URL? {
        didSet { updateServerKey() }
    }

    /// Optional (in case you later want authenticated stream URLs).
    var apiToken: String?

    private var serverKey: String = "default" // used in progress keys

    // MARK: - Private internals

    private let player = AVPlayer()
    private var timeObserverToken: Any?

    private let progressStore: EpisodeProgressStoring

    // MARK: - Init / Deinit

    init(progressStore: EpisodeProgressStoring = UserDefaultsEpisodeProgressStore()) {
        self.progressStore = progressStore
        configureAudioSession()
        observePlayerTime()
        setupRemoteCommandCenter()
    }

    deinit {
        removeTimeObserver()
    }

    private func updateServerKey() {
        serverKey = serverURL?.absoluteString ?? "default"
    }

    // MARK: - Public API

    /// Load a new episode and optionally start playing it.
    ///
    /// - Parameters:
    ///   - libraryItem: The podcast/show for context (title, artwork).
    ///   - episode: The episode to play.
    ///   - audioURL: Fully-resolved stream or file URL.
    ///   - autoPlay: Start playing immediately.
    ///   - presentNowPlaying: Show the Now Playing sheet.
    ///   - resumeFromLastPosition: Seek to last saved position if available.
    func start(
        libraryItem: LibraryItem,
        episode: Episode,
        audioURL: URL,
        artworkURL: URL? = nil,
        autoPlay: Bool = true,
        presentNowPlaying: Bool = true,
        resumeFromLastPosition: Bool = true
    ) {
        currentLibraryItem = libraryItem
        currentEpisode = episode
        self.audioURL = audioURL

        self.currentLibraryItem = libraryItem
        self.currentEpisode = episode
        self.audioURL = audioURL

        // Prefer explicit artworkURL if provided, otherwise derive from item id
        if let explicitArtwork = artworkURL {
            self.artworkURL = explicitArtwork
        } else {
            self.artworkURL = URL.absCoverURL(
                base: serverURL,
                itemId: libraryItem.id,
                token: apiToken
            )
        }


        let playerItem = AVPlayerItem(url: audioURL)
        player.replaceCurrentItem(with: playerItem)

        // Reset timing
        currentTime = 0
        duration = playerItem.asset.duration.seconds
        chapters = []
        currentChapterIndex = nil

        // Try to load chapters from the asset
        loadChapters(from: playerItem.asset)

        if presentNowPlaying {
            isPresented = true
        }

        if resumeFromLastPosition,
           let serverURL = serverURL,
           let libraryId = libraryItem.libraryId,
           let epId = currentEpisode?.id,
           let saved = progressStore.loadProgress(
                serverKey: serverURL.absoluteString,
                libraryItemId: libraryId,
                episodeId: epId
            ),
           saved.time > 0, saved.time < saved.duration
        {
            seek(to: saved.time, quietly: true)
        }

        if autoPlay {
            play()
        } else {
            updateNowPlayingInfo()
        }
    }

    /// Play or resume.
    func play() {
        configureAudioSession()
        player.play()
        player.rate = playbackRate
        isPlaying = true
        updateNowPlayingInfo()
    }

    /// Pause.
    func pause() {
        player.pause()
        isPlaying = false
        updateNowPlayingInfo()
    }

    /// Toggle play/pause.
    func togglePlayPause() {
        isPlaying ? pause() : play()
    }

    /// Seek to time (seconds).
    func seek(to time: TimeInterval, quietly: Bool = false) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player.seek(to: cmTime) { [weak self] _ in
            guard let self else { return }
            self.currentTime = time
            if !quietly {
                self.updateNowPlayingInfo()
            }
            self.updateCurrentChapter()
        }
    }

    /// Skip forward by seconds.
    func skipForward(seconds: TimeInterval) {
        seek(to: currentTime + seconds)
    }

    /// Skip backward by seconds.
    func skipBackward(seconds: TimeInterval) {
        seek(to: max(currentTime - seconds, 0))
    }

    /// Jump to a specific chapter index if available.
    func jumpToChapter(at index: Int) {
        guard chapters.indices.contains(index) else { return }
        let chapter = chapters[index]
        seek(to: chapter.startTime)
    }

    /// Stop playback and clear state.
    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        isPlaying = false

        currentTime = 0
        duration = 0
        chapters = []
        currentChapterIndex = nil

        currentEpisode = nil
        currentLibraryItem = nil
        audioURL = nil
        artworkURL = nil
        isPresented = false

        clearNowPlayingInfo()
    }

    // MARK: - Audio Session

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.allowBluetooth, .allowAirPlay])
            try session.setActive(true)
        } catch {
            print("DEBUG: Failed to configure audio session: \(error)")
        }
    }

    // MARK: - Time Observation & Progress Saving

    private func observePlayerTime() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)

        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            self.currentTime = time.seconds

            if let itemDuration = self.player.currentItem?.duration.seconds, itemDuration.isFinite {
                self.duration = itemDuration
            }

            self.updateCurrentChapter()
            self.saveProgressIfNeeded()
            self.updateNowPlayingInfo(playbackOnly: true)
        }
    }

    private func removeTimeObserver() {
        if let token = timeObserverToken {
            player.removeTimeObserver(token)
            timeObserverToken = nil
        }
    }

    private func saveProgressIfNeeded() {
        guard
            let serverURL,
            let libraryId = currentLibraryItem?.libraryId,
            let episodeId = currentEpisode?.id,
            duration > 0
        else { return }

        progressStore.saveProgress(
            serverKey: serverURL.absoluteString,
            libraryItemId: libraryId,
            episodeId: episodeId,
            time: currentTime,
            duration: duration
        )
    }

    // MARK: - Chapters

    private func loadChapters(from asset: AVAsset) {
        let groups = asset.chapterMetadataGroups(bestMatchingPreferredLanguages: [])

        guard !groups.isEmpty else { return }

        var loaded: [Chapter] = []

        for group in groups {
            let timeRange = group.timeRange
            let startSeconds = timeRange.start.seconds

            let items = group.items
            let titleItem = items.first(where: { $0.commonKey?.rawValue == "title" })
            let title = titleItem?.stringValue ?? "Chapter \(loaded.count + 1)"

            loaded.append(Chapter(title: title, startTime: startSeconds))
        }

        // Sort by start time just in case
        loaded.sort { $0.startTime < $1.startTime }
        DispatchQueue.main.async {
            self.chapters = loaded
            self.updateCurrentChapter()
        }
    }

    private func updateCurrentChapter() {
        guard !chapters.isEmpty else {
            currentChapterIndex = nil
            return
        }

        let time = currentTime
        var index: Int?

        for (i, chapter) in chapters.enumerated() {
            let nextStart = chapters.indices.contains(i + 1) ? chapters[i + 1].startTime : duration
            if time >= chapter.startTime && time < nextStart {
                index = i
                break
            }
        }

        currentChapterIndex = index
    }

    // MARK: - Now Playing / Lock Screen

    private func updateNowPlayingInfo(playbackOnly: Bool = false) {
        guard let episode = currentEpisode else { return }

        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]

        if !playbackOnly {
            info[MPMediaItemPropertyTitle] = episodeTitle(for: episode)
            info[MPMediaItemPropertyAlbumTitle] = showTitle(for: episode)
            info[MPNowPlayingInfoPropertyPlaybackRate] = playbackRate

            if let artworkURL = artworkURL {
                loadArtwork(from: artworkURL) { image in
                    guard let image else { return }
                    let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                    var currentInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                    currentInfo[MPMediaItemPropertyArtwork] = artwork
                    MPNowPlayingInfoCenter.default().nowPlayingInfo = currentInfo
                }
            }
        }

        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? playbackRate : 0

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        print("DEBUG: Updating Now Playing – title=\(episodeTitle(for: episode)), time=\(currentTime), playing=\(isPlaying)")
    }

    private func clearNowPlayingInfo() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: - Remote Commands

    private func setupRemoteCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.play()
            return .success
        }

        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }

        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.togglePlayPause()
            return .success
        }

        commandCenter.skipForwardCommand.preferredIntervals = [30]
        commandCenter.skipForwardCommand.addTarget { [weak self] _ in
            self?.skipForward(seconds: 30)
            return .success
        }

        commandCenter.skipBackwardCommand.preferredIntervals = [15]
        commandCenter.skipBackwardCommand.addTarget { [weak self] _ in
            self?.skipBackward(seconds: 15)
            return .success
        }
    }

    // MARK: - Helpers

    private func episodeTitle(for episode: Episode) -> String {
        episode.title
    }

    private func showTitle(for episode: Episode) -> String {
        // Use the parent library item's metadata title if available.
        if let title = currentLibraryItem?.media?.metadata?.title, !title.isEmpty {
            return title
        }
        return "Podcast"
    }

    private func loadArtwork(from url: URL, completion: @escaping (UIImage?) -> Void) {
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data, let image = UIImage(data: data) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            DispatchQueue.main.async { completion(image) }
        }.resume()
    }
}

