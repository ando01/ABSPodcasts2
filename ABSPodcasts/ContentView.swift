import SwiftUI

struct ContentView: View {
    @EnvironmentObject var playerManager: PlayerManager
    @EnvironmentObject var playbackSettings: PlaybackSettingsViewModel

    @State private var serverURL: String = ""
    @State private var apiToken: String = ""

    @State private var libraries: [ABSClient.Library] = []
    @State private var isLoadingLibraries: Bool = false
    @State private var librariesErrorMessage: String?

    var body: some View {
        ZStack(alignment: .bottom) {

            // MAIN APP UI
            NavigationStack {
                Form {
                    // Server + token inputs
                    Section(header: Text("Audiobookshelf Server")) {
                        TextField("Server URL (e.g. https://abs.example.com)", text: $serverURL)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)

                        TextField("API Token", text: $apiToken)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                    }

                    // Connect / load libraries
                    Section {
                        Button {
                            Task {
                                await loadLibraries()
                            }
                        } label: {
                            if isLoadingLibraries {
                                HStack {
                                    ProgressView()
                                    Text("Connecting…")
                                }
                            } else {
                                Text("Connect & Load Libraries")
                            }
                        }
                        .disabled(serverURL.isEmpty || apiToken.isEmpty)
                    }

                    // Libraries list
                    if !libraries.isEmpty {
                        Section(header: Text("Libraries")) {
                            ForEach(libraries) { library in
                                NavigationLink {
                                    LibraryDetailView(
                                        library: library,
                                        serverURL: serverURL,
                                        apiToken: apiToken
                                    )
                                } label: {
                                    HStack(spacing: 10) {
                                        // simple icon based on media type
                                        Image(systemName: library.mediaType.lowercased().contains("podcast") ? "dot.radiowaves.left.and.right" : "book")
                                            .foregroundStyle(.blue)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(library.name)
                                                .font(.subheadline)
                                                .fontWeight(.medium)
                                            Text(library.mediaType.capitalized)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Error message
                    if let msg = librariesErrorMessage {
                        Section {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.yellow)
                                Text(msg)
                                    .font(.subheadline)
                            }
                        }
                    }
                }
                .navigationTitle("ABS Podcasts")
            }

            // FLOATING MINI PLAYER
            if playerManager.isActive && !playerManager.isPresented {
                MiniPlayerView()
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        // FULL NOW PLAYING SHEET
        .sheet(isPresented: $playerManager.isPresented) {
            if let episode = playerManager.currentEpisode,
               let url = playerManager.audioURL {
                NavigationStack {
                    NowPlayingView(
                        episode: episode,
                        audioURL: url,
                        artworkURL: playerManager.artworkURL,
                        apiToken: nil
                    )
                    .environmentObject(playbackSettings)
                }
            } else {
                Text("No active item")
            }
        }
    }

    // MARK: - Networking

    private func loadLibraries() async {
        guard let url = URL(string: serverURL), !apiToken.isEmpty else {
            await MainActor.run {
                librariesErrorMessage = "Please enter a valid server URL and API token."
            }
            return
        }

        await MainActor.run {
            isLoadingLibraries = true
            librariesErrorMessage = nil
        }

        let client = ABSClient(serverURL: url, apiToken: apiToken)

        do {
            let libs = try await client.fetchLibraries()
            await MainActor.run {
                self.libraries = libs
                self.isLoadingLibraries = false
            }
        } catch {
            await MainActor.run {
                self.isLoadingLibraries = false
                self.librariesErrorMessage = error.localizedDescription
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(PlaybackSettingsViewModel())
        .environmentObject(PlayerManager())
}

