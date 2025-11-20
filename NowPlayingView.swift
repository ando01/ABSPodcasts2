import SwiftUI
import AVFoundation
import MediaPlayer
import UIKit
import Combine

struct NowPlayingView: View {
    let episode: ABSClient.Episode
    let audioURL: URL
    let artworkURL: URL?
    let apiToken: String?   // reserved for future header-based auth

    @EnvironmentObject var playbackSettings: PlaybackSettingsViewModel

    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var timeObserverToken: Any?
    @State private var playbackSpeed: Float = 1.0
    @State private var artworkImage: UIImage?
    @State private var cancellables = Set<AnyCancellable>()

    @State private var savedProgress: PlaybackProgressManager.Progress?
    @State private var showResumeAlert = false

    private var speeds: [Float] { playbackSettings.settings.allowedSpeeds }
    private let progressManager = PlaybackProgressManager.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {

                // Artwork
                ZStack {
                    if let artworkImage {
                        Image(uiImage: artworkImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 280, maxHeight: 280)
                            .cornerRadius(24)
                            .shadow(color: .black.opacity(0.35), radius: 18, x: 0, y: 12)
                    } else if let url = artworkURL {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .empty:
                                placeholderArtwork.overlay(ProgressView())
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: 280, maxHeight: 280)
                                    .cornerRadius(24)
                                    .shadow(color: .black.opacity(0.35), radius: 18, x: 0, y: 12)
                            case .failure:
                                placeholderArtwork
                            @unknown default:
                                placeholderArtwork
                            }
                        }
                    } else {
                        placeholderArtwork
                    }
                }
                .padding(.top, 40)

                // Title + date
                VStack(spacing: 8) {
                    Text(episode.title)
                        .font(.title2.weight(.bold))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)

                    if let date = episode.bestDate {
                        Text(date.formatted(date: .abbreviated, time: .shortened))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                // Progress slider
                VStack(spacing: 8) {
                    Slider(
                        value: Binding(
                            get: { currentTime },
                            set: { newValue in
                                currentTime = newValue
                                seek(to: newValue)
                            }),
                        in: 0...max(duration, 1)
                    )
                    .tint(.blue)

                    HStack {
                        Text(formatTime(currentTime))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)

                        Spacer()

                        Text("-\(formatTime(max(duration - currentTime, 0)))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)

                // Transport controls
                HStack(spacing: 50) {
                    Button {
                        skip(by: -Double(playbackSettings.settings.skipBackSeconds))
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color.gray.opacity(0.12))
                                .frame(width: 60, height: 60)
                            // Icon fixed at 15s, behavior uses custom value
                            Image(systemName: "gobackward.15")
                                .font(.title2)
                        }
                    }
                    .buttonStyle(ScaleButtonStyle())

                    Button {
                        togglePlayback()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.blue, Color.purple],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 80, height: 80)
                                .shadow(color: .blue.opacity(0.6), radius: 18, x: 0, y: 12)

                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 32, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                    .buttonStyle(ScaleButtonStyle())

                    Button {
                        skip(by: Double(playbackSettings.settings.skipForwardSeconds))
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color.gray.opacity(0.12))
                                .frame(width: 60, height: 60)
                            // Icon fixed at 30s, behavior uses custom value
                            Image(systemName: "goforward.30")
                                .font(.title2)
                        }
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
                .padding(.vertical, 8)

                // Speed buttons
                VStack(spacing: 10) {
                    HStack {
                        Image(systemName: "gauge.medium")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Playback Speed")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.2gx", playbackSpeed))
                            .font(.caption.weight(.semibold))
                    }
                    .padding(.horizontal)

                    HStack(spacing: 10) {
                        ForEach(speeds, id: \.self) { speed in
                            Button {
                                setSpeed(speed)
                            } label: {
                                Text(String(format: "%.2gx", speed))
                                    .font(.subheadline.weight(.medium))
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 12)
                                    .background(
                                        Group {
                                            if playbackSpeed == speed {
                                                LinearGradient(
                                                    colors: [Color.blue, Color.purple],
                                                    startPoint: .leading,
                                                    endPoint: .trailing
                                                )
                                                .clipShape(Capsule())
                                            } else {
                                                Capsule()
                                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                            }
                                        }
                                    )
                                    .foregroundColor(playbackSpeed == speed ? .white : .primary)
                            }
                        }
                    }
                }
                .padding(.bottom, 24)
            }
            .padding(.horizontal)
        }
        .background(
            LinearGradient(
                colors: [Color(.systemBackground), Color(.secondarySystemBackground)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .navigationTitle("Now Playing")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Resume Playback?", isPresented: $showResumeAlert) {
            Button("Resume") {
                if let progress = savedProgress {
                    seek(to: progress.currentTime)
                }
            }
            Button("Start Over", role: .destructive) {
                progressManager.clearProgress(for: episode.id)
                seek(to: 0)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let progress = savedProgress {
                Text("Resume from \(progressManager.formatTime(progress.currentTime))?")
            }
        }
        .onAppear {
            playbackSpeed = playbackSettings.settings.defaultSpeed
            setupAudioSession()
            setupPlayer()
            setupRemoteCommands()
            loadArtwork()
            checkForSavedProgress()
        }
        .onDisappear {
            saveCurrentProgress()
            cleanupPlayer()
        }
    }

    // MARK: - Artwork placeholder

    private var placeholderArtwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.gray.opacity(0.2))
                .frame(width: 280, height: 280)
            Image(systemName: "waveform.and.mic")
                .font(.system(size: 64))
                .foregroundStyle(.gray)
        }
    }

    // MARK: - Audio session

    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [])
            try session.setActive(true)
        } catch {
            print("⚠️ Audio session error: \(error)")
        }
    }

    // MARK: - Player

    private func setupPlayer() {
        let player = AVPlayer(url: audioURL)
        self.player = player

        if let item = player.currentItem {
            item.publisher(for: \.status)
                .sink { status in
                    if status == .failed {
                        print("⚠️ Player item failed: \(String(describing: item.error))")
                    }
                }
                .store(in: &cancellables)

            let asset = item.asset
            Task {
                do {
                    let cmDuration = try await asset.load(.duration)
                    let secs = CMTimeGetSeconds(cmDuration)
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

        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        let token = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            self.currentTime = time.seconds
            self.updateNowPlayingInfo()

            // autosave every ~5 seconds
            if Int(self.currentTime) % 5 == 0 {
                self.saveCurrentProgress()
            }
        }
        timeObserverToken = token
    }

    private func togglePlayback() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            saveCurrentProgress()
        } else {
            player.play()
            player.rate = playbackSpeed
        }
        isPlaying.toggle()
        updateNowPlayingInfo()
    }

    private func seek(to time: Double) {
        guard let player else { return }
        let clamped = max(0, min(time, duration))
        let cm = CMTime(seconds: clamped, preferredTimescale: 600)
        player.seek(to: cm) { _ in
            self.currentTime = clamped
            self.updateNowPlayingInfo()
        }
    }

    private func skip(by delta: Double) {
        let newTime = currentTime + delta
        seek(to: newTime)
    }

    private func setSpeed(_ speed: Float) {
        playbackSpeed = speed
        if isPlaying {
            player?.rate = speed
        }
        updateNowPlayingInfo()
    }

    private func cleanupPlayer() {
        if let player, let token = timeObserverToken {
            player.removeTimeObserver(token)
        }
        timeObserverToken = nil
        player = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: - Remote commands

    private func setupRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { _ in
            if let player = self.player, !self.isPlaying {
                player.play()
                player.rate = self.playbackSpeed
                self.isPlaying = true
                self.updateNowPlayingInfo()
            }
            return .success
        }

        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { _ in
            if let player = self.player, self.isPlaying {
                player.pause()
                self.isPlaying = false
                self.updateNowPlayingInfo()
                self.saveCurrentProgress()
            }
            return .success
        }


        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { _ in
            self.togglePlayback()
            return .success
        }


        commandCenter.skipForwardCommand.isEnabled = true
        commandCenter.skipForwardCommand.preferredIntervals =
            [NSNumber(value: playbackSettings.settings.skipForwardSeconds)]
        commandCenter.skipForwardCommand.addTarget { _ in
            self.skip(by: Double(self.playbackSettings.settings.skipForwardSeconds))
            return .success
        }


        commandCenter.skipBackwardCommand.isEnabled = true
        commandCenter.skipBackwardCommand.preferredIntervals =
            [NSNumber(value: playbackSettings.settings.skipBackSeconds)]
        commandCenter.skipBackwardCommand.addTarget { _ in
            self.skip(by: -Double(self.playbackSettings.settings.skipBackSeconds))
            return .success
        }

    }

    // MARK: - Now Playing info

    private func updateNowPlayingInfo() {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: episode.title,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(playbackSpeed) : 0.0,
            MPMediaItemPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue
        ]

        if duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }

        if let artworkImage {
            let artwork = MPMediaItemArtwork(boundsSize: artworkImage.size) { _ in artworkImage }
            info[MPMediaItemPropertyArtwork] = artwork
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    // MARK: - Artwork loading

    private func loadArtwork() {
        guard artworkImage == nil, let url = artworkURL else { return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data, let image = UIImage(data: data) else { return }
            DispatchQueue.main.async {
                self.artworkImage = image
                self.updateNowPlayingInfo()
            }
        }.resume()
    }

    // MARK: - Progress

    private func checkForSavedProgress() {
        if let progress = progressManager.loadProgress(for: episode.id),
           progress.progressPercentage > 5,
           !progress.isCompleted {
            savedProgress = progress
            showResumeAlert = true
        }
    }

    private func saveCurrentProgress() {
        guard duration > 0 else { return }
        progressManager.saveProgress(
            episodeId: episode.id,
            currentTime: currentTime,
            duration: duration
        )
    }

    // MARK: - Helpers

    private func formatTime(_ seconds: Double) -> String {
        progressManager.formatTime(seconds)
    }
}

// MARK: - Scale button style

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}









