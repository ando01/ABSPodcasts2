import SwiftUI

struct NowPlayingView: View {
    @EnvironmentObject var playerManager: PlayerManager

    // simple local speeds – we can wire these to your Settings later if you want
    private let availableSpeeds: [Double] = [0.75, 1.0, 1.25, 1.5, 2.0]

    var body: some View {
        VStack(spacing: 24) {
            if let episode = playerManager.currentEpisode {
                // Artwork
                artworkSection

                // Title
                Text(episode.title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                // Progress
                progressSection

                // Transport controls
                controlsSection

                // Speed controls
                speedSection
            } else {
                Spacer()
                Text("Nothing is playing")
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding()
        .presentationDetents([.medium, .large])
    }

    // MARK: - Artwork

    private var artworkSection: some View {
        Group {
            if let url = playerManager.artworkURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ZStack {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.gray.opacity(0.2))
                            ProgressView()
                        }
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
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
        .frame(width: 220, height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(radius: 8)
        .padding(.top, 32)
    }

    private var placeholderArtwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.gray.opacity(0.2))
            Image(systemName: "headphones")
                .font(.system(size: 64))
                .foregroundStyle(.gray)
        }
    }

    // MARK: - Progress

    private var progressSection: some View {
        VStack(spacing: 8) {
            Slider(
                value: Binding(
                    get: { playerManager.currentTime },
                    set: { newValue in
                        playerManager.seek(to: newValue)
                    }
                ),
                in: 0...max(playerManager.duration, 1.0)
            )
            .tint(.blue)

            HStack {
                Text(formatTime(playerManager.currentTime))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formatTime(playerManager.duration))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Transport

    private var controlsSection: some View {
        HStack(spacing: 40) {
            Button {
                playerManager.skip(by: -15)
            } label: {
                Image(systemName: "gobackward.15")
                    .font(.title2)
            }

            Button {
                playerManager.togglePlayPause()
            } label: {
                Image(systemName: playerManager.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 60))
            }

            Button {
                playerManager.skip(by: 30)
            } label: {
                Image(systemName: "goforward.30")
                    .font(.title2)
            }
        }
        .padding(.top, 12)
    }

    // MARK: - Speed control

    private var speedSection: some View {
        VStack(spacing: 8) {
            Text("Playback Speed")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                ForEach(availableSpeeds, id: \.self) { speed in
                    Button {
                        playerManager.setSpeed(speed)
                    } label: {
                        Text(String(format: "%.2gx", speed))
                            .font(.caption)
                            .fontWeight(speed == playerManager.playbackSpeed ? .bold : .regular)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(
                                        speed == playerManager.playbackSpeed
                                        ? Color.blue.opacity(0.2)
                                        : Color.gray.opacity(0.15)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Helpers

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
}

