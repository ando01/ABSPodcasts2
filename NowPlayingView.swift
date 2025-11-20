
s: 20, x: 0, y: 10)
                                    .transition(.scale.combined(with: .opacity))
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

                // Title and Date
                VStack(spacing: 8) {
                    Text(episode.title)
                        .font(.title2)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)

                    if let date = episode.bestDate {
                        Text(date.formatted(date: .abbreviated, time: .shortened))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                // Progress slider with enhanced design
                VStack(spacing: 12) {
                    // Custom styled slider
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
                    .tint(.blue)
                    
                    // Time labels
                    HStack {
                        Text(formatTime(currentTime))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Spacer()
                        Text(formatTime(duration))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .padding(.horizontal, 32)

                // Transport controls with animations
                HStack(spacing: 50) {
                    // Skip backward button
                    Button {
                        skip(by: -15)
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color.gray.opacity(0.1))
                                .frame(width: 60, height: 60)
                            
                            Image(systemName: "gobackward.15")
                                .font(.title2)
                                .foregroundStyle(.primary)
                        }
                    }
                    .buttonStyle(ScaleButtonStyle())

                    // Play/Pause button with animation
                    Button(action: togglePlayback) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.blue, Color.blue.opacity(0.8)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 90, height: 90)
                                .shadow(color: .blue.opacity(0.4), radius: 12, x: 0, y: 6)
                            
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(.white)
                                .contentTransition(.symbolEffect(.replace))
                        }
                    }
                    .buttonStyle(ScaleButtonStyle())

                    // Skip forward button
                    Button {
                        skip(by: 30)
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color.gray.opacity(0.1))
                                .frame(width: 60, height: 60)
                            
                            Image(systemName: "goforward.30")
                                .font(.title2)
                                .foregroundStyle(.primary)
                        }
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
                .padding(.vertical, 8)

                // Speed control with enhanced design
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "gauge.medium")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Playback Speed")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 8) {
                        ForEach(speeds, id: \.self) { speed in
                            Button {
                                withAnimation(.spring(response: 0.3)) {
                                    setSpeed(speed)
                                }
                            } label: {
                                Text(String(format: "%.2gx", speed))
                                    .font(.subheadline)
                                    .fontWeight(speed == playbackSpeed ? .bold : .regular)
                                    .foregroundStyle(speed == playbackSpeed ? .white : .primary)
                                    .frame(width: 60, height: 36)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(speed == playbackSpeed ? Color.blue : Color.gray.opacity(0.1))
                                    )
                            }
                            .buttonStyle(ScaleButtonStyle())
                        }
                    }
                }
                .padding(.horizontal, 24)

                // Description (collapsible)
                if let desc = episode.description, !desc.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "text.alignleft")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Description")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)
                        }
                        
                        Text(desc)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(5)
                    }
                    .padding(.horizontal, 32)
                    .padding(.top, 8)
                }

                Spacer(minLength: 40)
            }
        }
        .navigationTitle("Now Playing")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Resume Playback", isPresented: $showResumeAlert) {
            Button("Resume") {
                if let progress = savedProgress {
                    seek(to: progress.currentTime)
                }
            }
            Button("Start Over") {
                progressManager.clearProgress(for: episode.id)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let progress = savedProgress {
                Text("Resume from \(progressManager.formatTime(progress.currentTime))?")
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.6)) {
                setupAudioSession()
                setupRemoteCommands()
                setupPlayer()
                loadArtwork()
                checkForSavedProgress()
            }
        }
        .onDisappear {
            saveCurrentProgress()
            cleanupPlayer()
        }
    }

    private var placeholderArtwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.gray.opacity(0.2))
                .frame(width: 280, height: 280)
            Image(systemName: "music.note")
                .font(.system(size: 72))
                .foregroundStyle(.gray)
        }
    }

    // MARK: - Audio Session Setup
    
    private func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .spokenAudio, options: [])
            try audioSession.setActive(true)
        } catch {
            print("❌ Audio session setup failed: \(error)")
        }
    }

    // MARK: - Remote Command Center Setup
    
    private func setupRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
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
        
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [self] _ in
            self.player?.pause()
            DispatchQueue.main.async {
                self.isPlaying = false
                self.updateNowPlayingInfo()
                self.saveCurrentProgress()
            }
            return .success
        }
        
        commandCenter.skipForwardCommand.isEnabled = true
        commandCenter.skipForwardCommand.preferredIntervals = [30]
        commandCenter.skipForwardCommand.addTarget { [self] _ in
            DispatchQueue.main.async {
                self.skip(by: 30)
            }
            return .success
        }
        
        commandCenter.skipBackwardCommand.isEnabled = true
        commandCenter.skipBackwardCommand.preferredIntervals = [15]
        commandCenter.skipBackwardCommand.addTarget { [self] _ in
            DispatchQueue.main.async {
                self.skip(by: -15)
            }
            return .success
        }
        
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
    }

    // MARK: - Player setup & control

    private func setupPlayer() {
        let player = AVPlayer(url: audioURL)
        self.player = player
        
        if let playerItem = player.currentItem {
            playerItem.publisher(for: \.status)
                .sink { status in
                    if status == .failed, let error = playerItem.error {
                        print("❌ Player item failed: \(error.localizedDescription)")
                    }
                }
                .store(in: &cancellables)
            
            let asset = playerItem.asset
            Task {
                do {
                    let durationValue = try await asset.load(.duration)
                    let seconds = CMTimeGetSeconds(durationValue)

                    if seconds.isFinite && seconds > 0 {
                        await MainActor.run {
                            withAnimation {
                                self.duration = seconds
                                self.updateNowPlayingInfo()
                            }
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
            
            if Int(self.currentTime) % 5 == 0 {
                self.saveCurrentProgress()
            }
        }
        timeObserverToken = token

        updateNowPlayingInfo()
    }

    private func togglePlayback() {
        guard let player = player else { return }

        withAnimation(.spring(response: 0.3)) {
            if isPlaying {
                player.pause()
                saveCurrentProgress()
            } else {
                player.play()
                player.rate = playbackSpeed
            }
            isPlaying.toggle()
        }
        updateNowPlayingInfo()
    }

    private func seek(to seconds: Double) {
        guard let player = player else { return }
        let newTime = CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: newTime)
        currentTime = seconds
        updateNowPlayingInfo()
        saveCurrentProgress()
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
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60
        
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
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
                        withAnimation(.spring(response: 0.4)) {
                            self.artworkImage = img
                            self.isLoadingArtwork = false
                            self.updateNowPlayingInfo()
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    self.isLoadingArtwork = false
                }
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
    
    // MARK: - Progress Management
    
    private func checkForSavedProgress() {
        if let progress = progressManager.loadProgress(for: episode.id) {
            if progress.progressPercentage > 5 && !progress.isCompleted {
                savedProgress = progress
                showResumeAlert = true
            }
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
}

// MARK: - Scale Button Style

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
