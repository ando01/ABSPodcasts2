import SwiftUI

struct MiniPlayerView: View {
    @EnvironmentObject var playerManager: PlayerManager
    private let progressManager = PlaybackProgressManager.shared

    var body: some View {
        if let episode = playerManager.currentEpisode {
            Button {
                playerManager.present()
            } label: {
                HStack(spacing: 12) {
                    // Artwork thumbnail
                    if let url = playerManager.artworkURL {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .empty:
                                Color.gray.opacity(0.2)
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                            case .failure:
                                Color.gray.opacity(0.2)
                            @unknown default:
                                Color.gray.opacity(0.2)
                            }
                        }
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 44, height: 44)
                            .overlay(
                                Image(systemName: "waveform")
                                    .foregroundStyle(.gray)
                            )
                    }

                    // Title + time
                    VStack(alignment: .leading, spacing: 2) {
                        Text(episode.title)
                            .font(.subheadline)
                            .lineLimit(1)

                        HStack {
                            Text(progressManager.formatTime(playerManager.currentTime))
                            Text("·")
                            Text(
                                "-\(progressManager.formatTime(max(playerManager.duration - playerManager.currentTime, 0)))"
                            )
                        }
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // Play / pause
                    Button {
                        playerManager.togglePlayPause()
                    } label: {
                        Image(systemName: playerManager.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title3)
                            .padding(8)
                            .background(Circle().fill(Color.blue))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
                .padding(10)
                .background(
                    BlurView(style: .systemMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                )
            }
            .buttonStyle(.plain)
        }
    }
}

/// Simple UIKit blur wrapper for a translucent background.
struct BlurView: UIViewRepresentable {
    let style: UIBlurEffect.Style

    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: UIBlurEffect(style: style))
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {}
}

