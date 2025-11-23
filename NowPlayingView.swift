import SwiftUI

struct NowPlayingView: View {
    @EnvironmentObject var playerManager: PlayerManager
    @Environment(\.dismiss) private var dismiss

    // Customize your skip intervals here
    private let skipForwardInterval: TimeInterval = 30
    private let skipBackwardInterval: TimeInterval = 15

    var body: some View {
        ZStack {
            // Background blur-ish color
            Color(.systemBackground)
                .ignoresSafeArea()

            if let episode = playerManager.currentEpisode {
                VStack(spacing: 16) {
                    header(episode: episode)

                    Spacer().frame(height: 8)

                    artworkView()

                    episodeTitles(episode: episode)

                    progressSection()

                    playbackControls()

                    playbackRateButton()

                    chaptersSection()

                    Spacer(minLength: 12)
                }
                .padding(.horizontal)
                .padding(.top, 12)
            } else {
                // Fallback if nothing is loaded
                VStack(spacing: 16) {
                    Text("Nothing Playing")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Select an episode to start playback.")
                        .foregroundColor(.secondary)

                    Button("Close") {
                        dismiss()
                    }
                    .padding(.top, 8)
                }
            }
        }
    }

    // MARK: - Header

    private func header(episode: Episode) -> some View {
        HStack {
            Text("Now Playing")
                .font(.headline)

            Spacer()

            Button {
                playerManager.isPresented = false
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .imageScale(.large)
                    .padding(8)
            }
            .accessibilityLabel("Dismiss")
        }
    }

    // MARK: - Artwork

    private func artworkView() -> some View {
        Group {
            if let url = playerManager.artworkURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ZStack {
                            Rectangle()
                                .fill(Color.secondary.opacity(0.1))
                            ProgressView()
                        }
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
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
        .frame(maxWidth: 340, maxHeight: 340)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(radius: 10)
    }

    private var placeholderArtwork: some View {
        ZStack {
            Rectangle()
                .fill(Color.secondary.opacity(0.15))
            Image(systemName: "waveform.circle")
                .resizable()
                .scaledToFit()
                .padding(40)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Titles

    private func episodeTitles(episode: Episode) -> some View {
        VStack(spacing: 4) {
            Text(episode.title)
                .font(.title3)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            if let showTitle = playerManager.currentLibraryItem?.media?.metadata?.title,
               !showTitle.isEmpty {
                Text(showTitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    // MARK: - Progress / Scrubber

    private func progressSection() -> some View {
        VStack(spacing: 4) {
            Slider(
                value: Binding(
                    get: { playerManager.currentTime },
                    set: { newValue in
                        playerManager.seek(to: newValue)
                    }
                ),
                in: 0...(playerManager.duration > 0 ? playerManager.duration : 1),
                step: 1
            )

            HStack {
                Text(formatTime(playerManager.currentTime))
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                let remaining = max(playerManager.duration - playerManager.currentTime, 0)
                Text("-" + formatTime(remaining))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.top, 8)
    }

    private func formatTime(_ time: TimeInterval) -> String {
        guard time.isFinite else { return "--:--" }

        let totalSeconds = Int(time.rounded())
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }

    // MARK: - Playback Controls

    private func playbackControls() -> some View {
        HStack(spacing: 40) {
            Button {
                playerManager.skipBackward(seconds: skipBackwardInterval)
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "gobackward.15")
                        .font(.system(size: 26, weight: .semibold))
                    Text("\(Int(skipBackwardInterval))s")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            Button {
                playerManager.togglePlayPause()
            } label: {
                Image(systemName: playerManager.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 56, weight: .regular))
            }
            .buttonStyle(.plain)

            Button {
                playerManager.skipForward(seconds: skipForwardInterval)
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "goforward.30")
                        .font(.system(size: 26, weight: .semibold))
                    Text("\(Int(skipForwardInterval))s")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 12)
    }

    // MARK: - Playback Rate

    private func playbackRateButton() -> some View {
        // Cycle through common speeds
        let speeds: [Float] = [0.8, 1.0, 1.25, 1.5, 2.0]
        let current = playerManager.playbackRate
        let nextSpeed: Float = {
            guard let idx = speeds.firstIndex(of: current) else {
                return 1.0
            }
            let nextIndex = (idx + 1) % speeds.count
            return speeds[nextIndex]
        }()

        return Button {
            playerManager.playbackRate = nextSpeed
        } label: {
            Text(String(format: "%.2gx", current))
                .font(.caption)
                .fontWeight(.semibold)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.secondary.opacity(0.15))
                )
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }

    // MARK: - Chapters

    private func chaptersSection() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !playerManager.chapters.isEmpty {
                HStack {
                    Text("Chapters")
                        .font(.headline)
                    Spacer()
                }

                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(Array(playerManager.chapters.enumerated()), id: \.element.id) { index, chapter in
                            chapterRow(chapter: chapter, index: index)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 200)
            } else {
                // Optional: show nothing or a subtle message
                EmptyView()
            }
        }
        .padding(.top, 12)
    }

    private func chapterRow(chapter: Chapter, index: Int) -> some View {
        let isCurrent = (index == playerManager.currentChapterIndex)

        return Button {
            playerManager.jumpToChapter(at: index)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(chapter.title)
                        .font(.subheadline)
                        .lineLimit(1)
                    Text(formatTime(chapter.startTime))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if isCurrent {
                    Text("Now")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(Color.accentColor.opacity(0.15))
                        )
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isCurrent ? Color.accentColor.opacity(0.12) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

