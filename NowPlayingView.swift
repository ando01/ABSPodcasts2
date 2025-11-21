import SwiftUI

struct NowPlayingView: View {
    @EnvironmentObject var playerManager: PlayerManager
    @EnvironmentObject var playbackSettings: PlaybackSettingsViewModel
    @Environment(\.dismiss) private var dismiss

    private let progressManager = PlaybackProgressManager.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                artworkSection
                titleSection
                sliderSection
                controlsSection
                speedSection
            }
            .padding(.horizontal)
            .padding(.top, 32)
            .padding(.bottom, 24)
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
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    playerManager.stop()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
            }
        }
        .onAppear {
            // Apply default speed for this session if we haven't already.
            if playerManager.currentTime == 0 {
                playerManager.setSpeed(playbackSettings.settings.defaultSpeed)
            }
        }
    }

    // MARK: - Subviews

    private var artworkSection: some View {
        ZStack {
            if let url = playerManager.artworkURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .frame(width: 280, height: 280)
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
    }

    private var titleSection: some View {
        VStack(spacing: 8) {
            Text(playerManager.currentEpisode?.title ?? "Nothing Playing")
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
    }

    private var sliderSection: some View {
        VStack(spacing: 8) {
            Slider(
                value: Binding(
                    get: { playerManager.currentTime },
                    set: { newValue in
                        playerManager.seek(to: newValue)
                    }
                ),
                in: 0...max(playerManager.duration, 1)
            )
            .tint(.blue)

            HStack {
                Text(formatTime(playerManager.currentTime))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                Spacer()

                Text("-\(formatTime(max(playerManager.duration - playerManager.currentTime, 0)))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
    }

    private var controlsSection: some View {
        HStack(spacing: 50) {
            Button {
                playerManager.skip(by: -Double(playbackSettings.settings.skipBackSeconds))
            } label: {
                Circle()
                    .fill(Color.gray.opacity(0.12))
                    .frame(width: 60, height: 60)
                    .overlay(
                        Image(systemName: "gobackward.15")
                            .font(.title2)
                    )
            }

            Button {
                playerManager.togglePlayPause()
            } label: {
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
                    .overlay(
                        Image(systemName: playerManager.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(.white)
                    )
            }

            Button {
                playerManager.skip(by: Double(playbackSettings.settings.skipForwardSeconds))
            } label: {
                Circle()
                    .fill(Color.gray.opacity(0.12))
                    .frame(width: 60, height: 60)
                    .overlay(
                        Image(systemName: "goforward.30")
                            .font(.title2)
                    )
            }
        }
        .padding(.vertical, 8)
    }

    private var speedSection: some View {
        let speeds = playbackSettings.settings.allowedSpeeds

        return VStack(spacing: 10) {
            HStack {
                Image(systemName: "gauge.medium")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Playback Speed")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.2gx", playerManager.playbackSpeed))
                    .font(.caption.weight(.semibold))
            }
            .padding(.horizontal)

            HStack(spacing: 10) {
                ForEach(speeds, id: \.self) { speed in
                    Button {
                        playerManager.setSpeed(speed)
                    } label: {
                        Text(String(format: "%.2gx", speed))
                            .font(.subheadline.weight(.medium))
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(
                                Group {
                                    if playerManager.playbackSpeed == speed {
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
                            .foregroundColor(
                                playerManager.playbackSpeed == speed ? .white : .primary
                            )
                    }
                }
            }
        }
    }

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

    private func formatTime(_ seconds: Double) -> String {
        progressManager.formatTime(seconds)
    }
}

