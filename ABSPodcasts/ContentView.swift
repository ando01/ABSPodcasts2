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
                // Main app with global tab bar
                MainTabView(client: client)
                    // 👉 Attach the mini player *inside* the safe area,
                    // so it appears above the tab bar instead of on top of it.
                    .safeAreaInset(edge: .bottom) {
                        globalMiniPlayerBar
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

    /// A mini player that appears at the bottom of the app (above the tab bar)
    /// when something is currently loaded in the PlayerManager.
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
            } else {
                // No active item → no mini player, takes essentially no space
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

// MARK: - Main Tab View

/// Global bottom navigation bar: Home / Podcasts / Episodes.
struct MainTabView: View {
    let client: ABSClient

    var body: some View {
        TabView {
            // HOME
            HomeView(client: client)
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }

            // PODCASTS (for now this is also HomeView – you can swap to a dedicated podcasts view later)
            HomeView(client: client)
                .tabItem {
                    Label("Podcasts", systemImage: "dot.radiowaves.left.and.right")
                }

            // EPISODES placeholder (your per-podcast episodes screen is EpisodeListView)
            EpisodesTabPlaceholderView()
                .tabItem {
                    Label("Episodes", systemImage: "list.bullet")
                }
        }
    }
}

struct EpisodesTabPlaceholderView: View {
    var body: some View {
        NavigationStack {
            Text("Open a podcast to see its episodes. The Episodes screen for each show has filters for date, category, and tags.")
                .padding()
                .navigationTitle("Episodes")
        }
    }
}

