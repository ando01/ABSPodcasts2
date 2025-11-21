import SwiftUI

struct ContentView: View {
    @EnvironmentObject var playerManager: PlayerManager
    @EnvironmentObject var playbackSettings: PlaybackSettingsViewModel

    @State private var serverURL: String = ""
    @State private var apiToken: String = ""
    @State private var isConnected: Bool = false

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
    }

    // MARK: - Root navigation

    private var mainView: some View {
        NavigationStack {
            Group {
                if isConnected {
                    // After connecting, show list of libraries
                    LibrariesView(serverURL: serverURL, apiToken: apiToken)
                } else {
                    // Initial login form
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

    private func connectToServer() {
        // Simple validation – you already know the values work from your old app
        guard URL(string: serverURL) != nil, !apiToken.isEmpty else { return }
        isConnected = true
    }
}

// MARK: - Libraries list

/// Shows the list of libraries from Audiobookshelf and navigates into `LibraryDetailView`.
struct LibrariesView: View {
    let serverURL: String
    let apiToken: String

    @State private var libraries: [ABSClient.Library] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView("Loading libraries…")
                    Spacer()
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.subheadline)
            }

            ForEach(libraries) { library in
                NavigationLink(
                    destination: LibraryDetailView(
                        library: library,
                        serverURL: serverURL,
                        apiToken: apiToken
                    )
                ) {
                    HStack(spacing: 12) {
                        Image(systemName: iconName(for: library))
                            .font(.title2)
                            .frame(width: 32, height: 32)
                            .foregroundStyle(.primary)

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
                    .padding(.vertical, 6)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Libraries")
        .task {
            await loadLibraries()
        }
    }

    // MARK: - Helpers

    /// Map Audiobookshelf's library.icon / mediaType to a nice SF Symbol.
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

