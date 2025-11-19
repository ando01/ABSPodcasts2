import SwiftUI
import AVFoundation
import MediaPlayer
import UIKit

struct NowPlayingView: View {
    let episode: ABSClient.Episode
    let audioURL: URL
    let artworkURL: URL?

    @State private var player: AVPlayer?
    @State private var isPlaying: Bool = false
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var timeObserverToken: Any?
    @State private var playbackSpeed: Float = 1.0
    @State private var artworkImage: UIImage? = nil

    private let speeds: [Float] = [0.75, 1.0, 1.25, 1.5, 2.0]

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Artwork
                if let artworkImage {
                    Image(uiImage: artworkImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 260, maxHeight: 260)
                        .cornerRadius(18)
                } else if let artworkURL {
                    AsyncImage(url: artworkURL) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                                .frame(width: 200, height: 200)
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: 260, maxHeight: 260)
                                .cornerRadius(18)
                        case .failure:
                            placeholderArtwork
                        @unknown default:
                            placeholderArtwork
                        }
                    }
                } else {
                    placeholderArtwork
                }

                // Title
                Text(episode.title)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                // Date
                if let date = episode.bestDate {
                    Text(date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Slider + times
                VStack {
                    Slider(
                        value: Binding(
                            get: { currentTime },
                            set: { newValue in
                                currentTime = newValue
                                seek(to: newValue)
                            }
                        ),
                        in: 0...max(duration, 1)
                    )

                    HStack {
                        Text(formatTime(currentTime))
                        Spacer()
                        Text(formatTime(duration))
                    }
                    .font(.caption)
                }
                .padding(.horizontal)

                // Transport controls
                HStack(spacing: 40) {
                    Button {
                        skip(by: -15)
                    } label: {
                        Image(systemName: "gobackward.15")
                            .resizable()
                            .frame(width: 32, height: 32)
                    }

                    Button(action: togglePlayback) {
                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .resizable()
                            .frame(width: 80, height: 80)
                    }

                    Button {
                        skip(by: 30)
                    } label: {
                        Image(systemName: "goforward.30")
                            .resizable()
                            .frame(width: 32, height: 32)
                    }
                }
                .padding(.top, 8)

                // Speed control
                VStack(spacing: 8) {
                    Text("Speed")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        ForEach(speeds, id: \.self) { speed in
                            Button {
                                setSpeed(speed)
                            } label: {
                                Text(String(format: "%.2gx", speed))
                                    .font(.caption)
                                    .padding(.vertical, 4)
                                    .padding(.horizontal, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(speed == playbackSpeed ? Color.blue.opacity(0.2) : Color.clear)
                                    )
                            }
                        }
                    }
                }

                // Description
                if let desc = episode.description, !desc.isEmpty {
                    Text(desc)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                        .padding(.top, 8)
                }

                Spacer(minLength: 20)
            }
            .padding(.top, 20)
        }
        .navigationTitle("Now Playing")
        .onAppear {
            setupAudioSession()
            setupRemoteCommands()
            setupPlayer()
            loadArtwork()
        }
        .onDisappear {
            cleanupPlayer()
        }
    }

    private var placeholderArtwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.gray.opacity(0.2))
                .frame(width: 220, height: 220)
            Image(systemName: "music.note")
                .font(.system(size: 48))
                .foregroundStyle(.gray)
        }
    }

    // MARK: - Audio Session Setup
    
    private func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .spokenAudio, options: [])
            try audioSession.setActive(true)
            print("✅ Audio session configured")
        } catch {
            print("❌ Audio session setup failed: \(error)")
        }
    }

    // MARK: - Remote Command Center Setup
    
    private func setupRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        // Play command
        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [self] _ in
            if let player = self.player {
                player.play()
                player.rate = self.playbackSpeed
                DispatchQueue.main.async {
                    self.isPlaying = true
                    self.updateNowPlayingInfo()
                }
            }
            return .success
        }
        
        // Pause command
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [self] _ in
            self.player?.pause()
            DispatchQueue.main.async {
                self.isPlaying = false
                self.updateNowPlayingInfo()
            }
            return .success
        }
        
        // Skip forward (30 seconds)
        commandCenter.skipForwardCommand.isEnabled = true
        commandCenter.skipForwardCommand.preferredIntervals = [30]
        commandCenter.skipForwardCommand.addTarget { [self] _ in
            DispatchQueue.main.async {
                self.skip(by: 30)
            }
            return .success
        }
        
        // Skip backward (15 seconds)
        commandCenter.skipBackwardCommand.isEnabled = true
        commandCenter.skipBackwardCommand.preferredIntervals = [15]
        commandCenter.skipBackwardCommand.addTarget { [self] _ in
            DispatchQueue.main.async {
                self.skip(by: -15)
            }
            return .success
        }
        
        // Change playback position (scrubbing)
        commandCenter.changePlaybackPositionCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.addTarget { [self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            DispatchQueue.main.async {
                self.seek(to: event.positionTime)
            }
            return .success
        }
        
        print("✅ Remote commands configured")
    }

    // MARK: - Player setup & control

    private func setupPlayer() {
        let player = AVPlayer(url: audioURL)
        self.player = player

        if let item = player.currentItem {
            let asset = item.asset

            Task {
                do {
                    let durationValue = try await asset.load(.duration)
                    let seconds = CMTimeGetSeconds(durationValue)

                    if seconds.isFinite && seconds > 0 {
                        await MainActor.run {
                            self.duration = seconds
                            print("✅ Loaded duration = \(seconds)")
                            self.updateNowPlayingInfo()
                        }
                    }
                } catch {
                    print("❌ Failed to load duration: \(error)")
                }
            }
        }

        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        let token = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            self.currentTime = time.seconds
            self.updateNowPlayingInfo()
        }
        timeObserverToken = token

        updateNowPlayingInfo()
    }

    private func togglePlayback() {
        guard let player = player else { return }

        if isPlaying {
            player.pause()
        } else {
            player.play()
            player.rate = playbackSpeed
        }
        isPlaying.toggle()
        updateNowPlayingInfo()
    }

    private func seek(to seconds: Double) {
        guard let player = player else { return }
        let newTime = CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: newTime)
        currentTime = seconds
        updateNowPlayingInfo()
    }

    private func skip(by delta: Double) {
        let target = max(0, min((currentTime + delta), duration))
        seek(to: target)
    }

    private func setSpeed(_ speed: Float) {
        playbackSpeed = speed
        if isPlaying {
            player?.rate = speed
        }
        updateNowPlayingInfo()
    }

    private func cleanupPlayer() {
        if let player = player, let token = timeObserverToken {
            player.removeTimeObserver(token)
        }
        player?.pause()
        player = nil
        timeObserverToken = nil
        isPlaying = false

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        
        // Disable remote commands
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.isEnabled = false
        commandCenter.pauseCommand.isEnabled = false
        commandCenter.skipForwardCommand.isEnabled = false
        commandCenter.skipBackwardCommand.isEnabled = false
        commandCenter.changePlaybackPositionCommand.isEnabled = false
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        let totalSeconds = Int(seconds)
        let m = totalSeconds / 60
        let s = totalSeconds % 60
        return String(format: "%d:%02d", m, s)
    }

    // MARK: - Artwork loading

    private func loadArtwork() {
        guard let artworkURL = artworkURL else { return }

        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: artworkURL)
                if let img = UIImage(data: data) {
                    await MainActor.run {
                        self.artworkImage = img
                        self.updateNowPlayingInfo()
                    }
                }
            } catch {
                print("❌ Failed to load artwork: \(error)")
            }
        }
    }

    // MARK: - Now Playing info

    private func updateNowPlayingInfo() {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: self.episode.title,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: self.currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: self.isPlaying ? Double(self.playbackSpeed) : 0.0,
            MPMediaItemPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue
        ]

        if self.duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = self.duration
        }

        if let artworkImage = self.artworkImage {
            let art = MPMediaItemArtwork(boundsSize: artworkImage.size) { _ in artworkImage }
            info[MPMediaItemPropertyArtwork] = art
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
