import SwiftUI

struct MiniPlayerView: View {
    @EnvironmentObject var playerManager: PlayerManager

    var body: some View {
        // Only show if there's something loaded
        if let episode = playerManager.currentEpisode {
            Button {
                // Tap mini player to open full-screen Now Playing sheet
                playerManager.isPresented = true
            } label: {
                HStack(spacing: 12) {
                    // Artwork thumb
                    artworkThumb

                    // Title + progress
                    VStack(alignment: .leading, spacing: 4) {
                        Text(episode.title)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .lineLimit(1)

                        if playerManager.duration > 0 {
                            // Simple progress bar
                            GeometryReader { geo in
                                let progress = CGFloat(playerManager.currentTime / playerManager.duration)
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(Color.secondary.opacity(0.25))
                                    Capsule()
                                        .fill(Color.blue)
                                        .frame(width: geo.size.width * min(max(progress, 0), 1))
                                }
                            }
                            .frame(height: 3)
                        } else {
                            Text("Loading…")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    // Play / Pause button
                    Button {
                        playerManager.togglePlayPause()
                    } label: {
                        Image(systemName: playerManager.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title3)
                            .padding(8)
                            .background(Color.blue.opacity(0.15))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(radius: 4)
        } else {
            EmptyView()
        }
    }

    // MARK: - Artwork thumb

    private var artworkThumb: some View {
        Group {
            if let url = playerManager.artworkURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.gray.opacity(0.2))
                            ProgressView()
                                .scaleEffect(0.6)
                        }
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        placeholderThumb
                    @unknown default:
                        placeholderThumb
                    }
                }
            } else {
                placeholderThumb
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var placeholderThumb: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.2))
            Image(systemName: "headphones")
                .font(.caption)
                .foregroundStyle(.gray)
        }
    }
}

