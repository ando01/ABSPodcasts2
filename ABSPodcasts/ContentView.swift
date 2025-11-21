import SwiftUI

struct ContentView: View {
    @EnvironmentObject var playerManager: PlayerManager
    @EnvironmentObject var playbackSettings: PlaybackSettingsViewModel

    // MARK: - UserDefaults keys

    private let serverURLKey = "ABS_ServerURL"
    private let apiTokenKey  = "ABS_APIToken"

    // MARK: - State

    @State private var serverURL: String = ""
    @State private var apiToken: String  = ""
    @State private var isConnected: Bool = false

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {
            mainView

            // Mini player overlaid at bottom
            if playerManager.isActive && !playerManager.isPresented {
                MiniPlayerView()
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $playerManager.isPresented) {
            NavigationStack {
                NowPlayingView()
                    .environmentObject(playerManager)
                    .environmentObject(playbackSettings)
            }
        }
        .onAppear(perform: loadSavedConnection)
    }

    // MARK: - Root navigation

    private var mainView: some View {
        NavigationStack {
            Group {
                if isConnected {
                    LibrariesView(
                        serverURL: serverURL,
                        apiToken: apiToken,
                        onLogout: handleLogout
                    )
                } else {
                    loginForm
                }
            }
        }
    }

    // MARK: - Login form

    private var loginForm: some View {
        Form {
            Section(header: Text("Audiobookshelf Server")) {
                TextField("Server URL (e.g. http://192.168.20.228:13378)", text: $serverURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)

                TextField("API Token", text: $apiToken)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
            }

            Section {
                Button(action: connectToServer) {
                    Text("Connect")
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle("Audiobookshelf Server")
    }

    // MARK: - Actions

    private func connectToServer() {
        guard URL(string: serverURL) != nil, !apiToken.isEmpty else { return }

        let defaults = UserDefaults.standard
        defaults.set(serverURL, forKey: serverURLKey)
        defaults.set(apiToken, forKey: apiTokenKey)

        isConnected = true
    }

    private func loadSavedConnection() {
        let defaults = UserDefaults.standard

        guard
            let savedURL   = defaults.string(forKey: serverURLKey),
            let savedToken = defaults.string(forKey: apiTokenKey),
            !savedURL.isEmpty,
            !savedToken.isEmpty,
            URL(string: savedURL) != nil
        else {
            return
        }

        serverURL   = savedURL
        apiToken    = savedToken
        isConnected = true
    }

    private func handleLogout() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: serverURLKey)
        defaults.removeObject(forKey: apiTokenKey)

        serverURL   = ""
        apiToken    = ""
        isConnected = false
    }
}

// MARK: - LibrariesView with "Pick up where you left off"

struct LibrariesView: View {
    let serverURL: String
    let apiToken: String
    let onLogout: () -> Void      // change server / log out

    @EnvironmentObject var playerManager: PlayerManager
    private let progressManager = PlaybackProgressManager.shared

    @State private var libraries: [ABSClient.Library] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            // 👉 Pick up where you left off section
            if let last = progressManager.loadLastPlayed() {
                Section(header: Text("Pick up where you left off")) {
                    Button {
                        resumeLastPlayed(last)
                    } label: {
                        HStack(spacing: 12) {
                            // Artwork
                            if let artString = last.artworkURLString,
                               let url = URL(string: artString) {
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
                                .frame(width: 48, height: 48)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            } else {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.gray.opacity(0.15))
                                    .frame(width: 48, height: 48)
                                    .overlay(
                                        Image(systemName: "play.circle.fill")
                                            .foregroundStyle(.gray)
                                    )
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(last.title)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(2)

                                if let progress = progressManager.loadProgress(for: last.episodeId) {
                                    Text(
                                        "At \(progressManager.formatTime(progress.currentTime)) " +
                                        "of \(progressManager.formatTime(progress.duration))"
                                    )
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                } else {
                                    Text("Tap to resume")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            Image(systemName: "play.fill")
                                .font(.title3)
                                .foregroundStyle(.blue)
                        }
                        .padding(8)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Loading / error
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView("Loading libraries…")
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.subheadline)
                    .listRowBackground(Color.clear)
            }

            // Libraries list
            ForEach(libraries) { library in
                NavigationLink(
                    destination: LibraryDetailView(
                        library: library,
                        serverURL: serverURL,
                        apiToken: apiToken
                    )
                ) {
                    HStack(spacing: 12) {

                        // Colored icon circle
                        ZStack {
                            Circle()
                                .fill(iconColor(for: library).opacity(0.18))
                                .frame(width: 40, height: 40)

                            Image(systemName: iconName(for: library))
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(iconColor(for: library))
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(library.name)
                                .font(.headline)

                            Text(library.mediaType.capitalized)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(.secondarySystemBackground))
                    )
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .navigationTitle("Libraries")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(role: .destructive) {
                    onLogout()
                } label: {
                    Text("Change Server")
                }
            }
        }
        .task {
            await loadLibraries()
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Resume last played

    private func resumeLastPlayed(_ last: PlaybackProgressManager.LastPlayedItem) {
        guard let streamURL = URL(string: last.streamURLString) else { return }
        let artworkURL = last.artworkURLString.flatMap { URL(string: $0) }

        // Minimal episode wrapper so PlayerManager can reuse NowPlaying
        let episode = ABSClient.Episode(
            id: last.episodeId,
            title: last.title,
            description: nil,
            pubDate: nil,
            publishedAt: nil,
            enclosure: ABSClient.Episode.Enclosure(
                url: last.streamURLString,
                type: "audio/mpeg",
                length: nil
            )
        )

        playerManager.start(
            episode: episode,
            audioURL: streamURL,
            artworkURL: artworkURL
        )

        // Seek to saved position if we have it
        if let progress = progressManager.loadProgress(for: last.episodeId) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                playerManager.seek(to: progress.currentTime)
            }
        }
    }

    // MARK: - Icon + Color helpers

    private func iconName(for library: ABSClient.Library) -> String {
        let icon = library.icon?.lowercased() ?? ""
        let type = library.mediaType.lowercased()

        if icon.contains("headphone") {
            return "headphones"
        } else if icon.contains("microphone") || icon.contains("mic") {
            return "mic.fill"
        }

        if type.contains("book") {
            return "books.vertical"
        } else if type.contains("podcast") {
            return "mic.and.waveform"
        }

        return "square.stack"
    }

    private func iconColor(for library: ABSClient.Library) -> Color {
        let type = library.mediaType.lowercased()
        if type.contains("book") {
            return .purple
        } else if type.contains("podcast") {
            return .orange
        } else {
            return .blue
        }
    }

    // MARK: - Networking

    private func loadLibraries() async {
        guard let baseURL = URL(string: serverURL) else { return }

        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }

        let client = ABSClient(serverURL: baseURL, apiToken: apiToken)

        do {
            let libs = try await client.fetchLibraries()
            await MainActor.run {
                self.libraries = libs
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
}

