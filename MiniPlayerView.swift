import SwiftUI

struct MiniPlayerView: View {
    @EnvironmentObject var playerManager: PlayerManager

    var body: some View {
        if let episode = playerManager.currentEpisode {
            Button {
                // expand to full player
                playerManager.isPresented = true
            } label: {
                HStack(spacing: 12) {
                    // Artwork thumbnail
                    if let url = playerManager.artworkURL {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .empty:
                                Color.gray.opacity(0.2)
                            case .success(let image):
                                image.resizable()
                            case .failure:
                                Color.gray.opacity(0.2)
                            @unknown default:
                                Color.gray.opacity(0.2)
                            }
                        }
                        .frame(width: 44, height: 44)
                        .cornerRadius(8)
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 44, height: 44)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(episode.title)
                            .font(.subheadline)
                            .lineLimit(1)
                        Text("Tap to expand")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.up")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(radius: 4)
            }
            .buttonStyle(.plain)
        }
    }
}

