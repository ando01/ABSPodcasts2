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
                        onLogout: handleLogout          // 👈 logout / change server
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

    /// Called when user taps "Connect"
    private func connectToServer() {
        guard URL(string: serverURL) != nil, !apiToken.isEmpty else { return }

        // Save to UserDefaults so we remember next launch
        let defaults = UserDefaults.standard
        defaults.set(serverURL, forKey: serverURLKey)
        defaults.set(apiToken, forKey: apiTokenKey)

        isConnected = true
    }

    /// Load saved connection (if any) on app startup.
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

    /// Clear saved credentials and go back to login form.
    private func handleLogout() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: serverURLKey)
        defaults.removeObject(forKey: apiTokenKey)

        serverURL   = ""
        apiToken    = ""
        isConnected = false
    }
}

struct LibrariesView: View {
    let serverURL: String
    let apiToken: String
    let onLogout: () -> Void      // 👈 callback to change server / log out

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
                .listRowBackground(Color.clear)
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.subheadline)
                    .listRowBackground(Color.clear)
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
                    onLogout()          // 👈 clears saved creds & returns to login
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

    // MARK: - Icon + Color helpers

    /// Map Audiobookshelf's icon/mediaType to an SF Symbol.
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

    /// Choose a color per library type.
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
