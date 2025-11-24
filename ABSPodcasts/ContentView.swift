import SwiftUI

struct ContentView: View {
    @EnvironmentObject var playerManager: PlayerManager

    // Persisted connection details
    @AppStorage("absServerURL") private var savedServerURL: String = ""
    @AppStorage("absApiToken") private var savedApiToken: String = ""

    @State private var client: ABSClient?
    @State private var isConnected: Bool = false

    var body: some View {
        ZStack(alignment: .bottom) {
            // Main app vs login
            Group {
                if let client, isConnected {
                    // Main app home screen
                    HomeView(client: client)
                } else {
                    // Login / connect screen
                    LoginView(isConnected: $isConnected, client: $client)
                }
            }

            // Global floating mini player, visible on any screen
            globalMiniPlayerBar
        }
        // Global Now Playing sheet
        .sheet(isPresented: $playerManager.isPresented) {
            NowPlayingView()
                .environmentObject(playerManager)
        }
        // Try to auto-connect on launch if we have saved credentials
        .onAppear {
            restoreSavedClientIfPossible()
        }
        // When connection status flips to true, persist credentials for next launch
        .onChange(of: isConnected) { newValue in
            if newValue {
                persistClient()
            }
        }
        // Keep PlayerManager in sync with the active server/token
        .onChange(of: client?.serverURL) { _ in
            syncPlayerManagerServer()
        }
        .onChange(of: client?.apiToken) { _ in
            syncPlayerManagerServer()
        }
    }

    // MARK: - Global Mini Player Bar

    /// A floating mini player that appears at the bottom of the app,
    /// regardless of which screen you're on.
    private var globalMiniPlayerBar: some View {
        Group {
            if let show = playerManager.currentLibraryItem,
               let episode = playerManager.currentEpisode {

                Button {
                    // Show full Now Playing sheet
                    playerManager.isPresented = true
                } label: {
                    HStack(spacing: 12) {
                        // Cover art
                        if let coverURL = URL.absCoverURL(
                            base: playerManager.serverURL,
                            itemId: show.id,
                            token: playerManager.apiToken,
                            width: 100
                        ) {
                            AsyncImage(url: coverURL) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFill()
                                default:
                                    Color.gray.opacity(0.2)
                                }
                            }
                            .frame(width: 40, height: 40)
                            .cornerRadius(6)
                        }

                        // Title + status
                        VStack(alignment: .leading, spacing: 2) {
                            Text(episode.title)
                                .font(.caption)
                                .lineLimit(1)
                            Text(playerManager.isPlaying ? "Playing" : "Paused")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        // Icon reflects playback state
                        Image(systemName: playerManager.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title3)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(
                        Rectangle()
                            .fill(Color(.systemBackground).opacity(0.95))
                            .shadow(radius: 4)
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal)
                .padding(.bottom, 4)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                EmptyView()
            }
        }
    }

    // MARK: - Persistence

    private func restoreSavedClientIfPossible() {
        guard !savedServerURL.isEmpty, !savedApiToken.isEmpty else { return }
        guard let url = URL(string: savedServerURL) else { return }

        let restoredClient = ABSClient(serverURL: url, apiToken: savedApiToken)
        self.client = restoredClient
        self.isConnected = true
        syncPlayerManagerServer()
    }

    private func persistClient() {
        guard let client else { return }
        savedServerURL = client.serverURL.absoluteString
        savedApiToken = client.apiToken
        syncPlayerManagerServer()
    }

    private func syncPlayerManagerServer() {
        guard let client else { return }
        playerManager.serverURL = client.serverURL
        playerManager.apiToken = client.apiToken
    }
}

