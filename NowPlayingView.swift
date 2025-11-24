import SwiftUI

struct NowPlayingView: View {
    @EnvironmentObject var playerManager: PlayerManager
    @Environment(\.dismiss) private var dismiss

    // Speed options in a horizontal row
    private let speedOptions: [Float] = [1.0, 1.2, 1.5, 2.0, 2.5, 3.0]

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // ARTWORK
                if let item = playerManager.currentLibraryItem,
                   let coverURL = URL.absCoverURL(
                        base: playerManager.serverURL,
                        itemId: item.id,
                        token: playerManager.apiToken,
                        width: 600
                   ) {
                    AsyncImage(url: coverURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                        default:
                            Color.gray.opacity(0.2)
                        }
                    }
                    .frame(maxHeight: 260)
                    .cornerRadius(18)
                    .padding(.horizontal)
                }

                // TITLES
                VStack(spacing: 4) {
                    Text(playerManager.currentEpisode?.title ?? "No Episode Playing")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .padding(.horizontal)

                    if let showTitle = playerManager.currentLibraryItem?.displayTitle {
                        Text(showTitle)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .padding(.horizontal)
                    }
                }

                // PROGRESS + TIMES
                VStack(spacing: 4) {
                    Slider(
                        value: Binding(
                            get: { playerManager.currentTime },
                            set: { newVal in
                                playerManager.seek(to: newVal)
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
                        Text(formatTime(playerManager.duration))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal)

                // TRANSPORT CONTROLS
                HStack(spacing: 40) {
                    Button {
                        playerManager.skipBackward(seconds: 15)
                    } label: {
                        VStack {
                            Image(systemName: "gobackward.15")
                                .font(.title2)
                            Text("-15s")
                                .font(.caption2)
                        }
                    }

                    Button {
                        playerManager.togglePlayPause()
                    } label: {
                        Image(systemName: playerManager.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 56))
                    }

                    Button {
                        playerManager.skipForward(seconds: 30)
                    } label: {
                        VStack {
                            Image(systemName: "goforward.30")
                                .font(.title2)
                            Text("+30s")
                                .font(.caption2)
                        }
                    }
                }

                // 🔊 HORIZONTAL SPEED CONTROL
                speedControl
                    .padding(.horizontal)
                    .padding(.top, 8)

                Spacer()
            }
            .padding(.top)
            .navigationTitle("Now Playing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Speed Control

    @ViewBuilder
    private var speedControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Speed")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                ForEach(speedOptions, id: \.self) { speed in
                    Button {
                        playerManager.playbackRate = speed
                    } label: {
                        Text(speedLabel(speed))
                            .font(.caption)               // smaller text
                            .padding(.vertical, 4)         // smaller height
                            .padding(.horizontal, 10)      // smaller width
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(playerManager.playbackRate == speed
                                          ? Color.blue.opacity(0.15)
                                          : Color(.systemGray5))
                            )
                            .foregroundColor(
                                playerManager.playbackRate == speed
                                ? .blue
                                : .primary
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }


    private func speedLabel(_ s: Float) -> String {
        if s == 1.0 { return "1×" }
        return String(format: "%.1f×", s)
    }

    // MARK: - Time Formatting

    private func formatTime(_ t: TimeInterval) -> String {
        guard t.isFinite && !t.isNaN else { return "--:--" }
        let totalSeconds = Int(t)
        let seconds = totalSeconds % 60
        let minutes = (totalSeconds / 60) % 60
        let hours = totalSeconds / 3600

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
}

