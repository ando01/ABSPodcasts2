import SwiftUI

struct ContentView: View {
    @EnvironmentObject var playerManager: PlayerManager

    // Persisted connection details
    @AppStorage("absServerURL") private var savedServerURL: String = ""
    @AppStorage("absApiToken") private var savedApiToken: String = ""

    @State private var client: ABSClient?
    @State private var isConnected: Bool = false

    var body: some View {
        Group {
            if let client, isConnected {
                MainTabView(client: client, onLogout: logout)
                    .overlay(alignment: .bottom) {
                        globalMiniPlayerBar
                            .padding(.bottom, 50) // keep mini player above tab bar
                    }
            } else {
                // Login / connect screen
                LoginView(isConnected: $isConnected, client: $client)
            }
        }
        // Global Now Playing sheet
        .sheet(isPresented: $playerManager.isPresented) {
            NowPlayingView()
                .environmentObject(playerManager)
        }
        // Auto-connect on launch
        .onAppear {
            restoreSavedClientIfPossible()
        }
        // Persist credentials when we successfully connect
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

    private var globalMiniPlayerBar: some View {
        Group {
            if let show = playerManager.currentLibraryItem,
               let episode = playerManager.currentEpisode {

                HStack(spacing: 12) {
                    // LEFT SIDE: artwork + text → tap opens full player
                    HStack(spacing: 12) {
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

                        VStack(alignment: .leading, spacing: 2) {
                            Text(episode.title)
                                .font(.caption)
                                .lineLimit(1)
                            Text(playerManager.isPlaying ? "Playing" : "Paused")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        playerManager.isPresented = true
                    }

                    Spacer()

                    // RIGHT SIDE: play/pause button → just toggles playback
                    Button {
                        playerManager.togglePlayPause()
                    } label: {
                        Image(systemName: playerManager.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(
                    Rectangle()
                        .fill(Color(.systemBackground).opacity(0.95))
                        .shadow(radius: 4)
                )
                .padding(.horizontal)
            } else {
                EmptyView()
            }
        }
    }

    // MARK: - Logout

    private func logout() {
        // Stop playback and clear player state
        playerManager.stop()

        // Clear client + connection
        client = nil
        isConnected = false

        // Clear stored credentials
        savedServerURL = ""
        savedApiToken = ""
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

// MARK: - Main Tab View

struct MainTabView: View {
    let client: ABSClient
    let onLogout: () -> Void

    var body: some View {
        TabView {
            // HOME
            HomeView(client: client, onLogout: onLogout)
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }

            // LIBRARY
            PodcastsView(client: client, onLogout: onLogout)
                .tabItem {
                    Label("Library", systemImage: "dot.radiowaves.left.and.right")
                }

            // EPISODES
            EpisodesTabView(client: client, onLogout: onLogout)
                .tabItem {
                    Label("Episodes", systemImage: "list.bullet")
                }
        }
    }
}

