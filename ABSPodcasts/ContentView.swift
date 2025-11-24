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
                // Main app home screen
                HomeView(client: client)
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

