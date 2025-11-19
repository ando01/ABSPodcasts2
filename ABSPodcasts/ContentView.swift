import SwiftUI

struct ContentView: View {
    @State private var serverURL: String = ""
    @State private var apiToken: String = ""
    @State private var statusMessage: String = "Not connected"
    @State private var isConnecting: Bool = false
    @State private var libraries: [ABSClient.Library] = []
    @State private var selectedLibraryId: String? = nil

    // UserDefaults keys
    private let keyServerURL = "ABS_ServerURL"
    private let keyApiToken = "ABS_ApiToken"
    private let keySelectedLibraryId = "ABS_SelectedLibraryId"

    var body: some View {
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

                // Connect button
                Section {
                    Button(action: connectToServer) {
                        if isConnecting {
                            ProgressView()
                                .frame(maxWidth: .infinity, alignment: .center)
                        } else {
                            Text("Connect & Load Libraries")
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                    .disabled(serverURL.isEmpty || apiToken.isEmpty || isConnecting)
                }

                // Status
                Section(header: Text("Status")) {
                    Text(statusMessage)
                        .font(.subheadline)
                }

                // Libraries list
                if !libraries.isEmpty {
                    Section(header: Text("Libraries")) {
                        ForEach(libraries) { library in
                            NavigationLink(
                                destination: LibraryDetailView(
                                    library: library,
                                    serverURL: serverURL,
                                    apiToken: apiToken
                                )
                            ) {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(library.name)
                                            .font(.body)
                                        Text(library.mediaType.capitalized)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if library.id == selectedLibraryId {
                                        Text("Last used")
                                            .font(.caption2)
                                            .padding(4)
                                            .background(
                                                Capsule().strokeBorder(lineWidth: 1)
                                            )
                                    }
                                }
                            }
                            // Remember last selected library when tapped
                            .simultaneousGesture(
                                TapGesture().onEnded {
                                    selectedLibraryId = library.id
                                    saveSettings()
                                }
                            )
                        }
                    }
                }
            }
            .navigationTitle("ABS Podcasts")
            .onAppear {
                loadSettings()
            }
        }
    }

    // MARK: - Actions

    private func connectToServer() {
        guard let url = URL(string: serverURL) else {
            statusMessage = "Invalid server URL."
            return
        }

        let client = ABSClient(serverURL: url, apiToken: apiToken)
        statusMessage = "Connecting and loading libraries..."
        isConnecting = true
        libraries = []

        // Save URL/token even before success so they persist across launches
        saveSettings()

        Task {
            do {
                let libs = try await client.fetchLibraries()
                await MainActor.run {
                    self.libraries = libs
                    self.statusMessage = "Found \(libs.count) libraries."

                    // If no saved library yet, default to the first one
                    if selectedLibraryId == nil, let first = libs.first {
                        selectedLibraryId = first.id
                    }

                    self.isConnecting = false
                    saveSettings()
                }
            } catch {
                await MainActor.run {
                    if let absErr = error as? ABSClient.ABSError {
                        statusMessage = absErr.localizedDescription
                    } else {
                        statusMessage = error.localizedDescription
                    }
                    isConnecting = false
                }
            }
        }
    }

    // MARK: - Persistence

    private func loadSettings() {
        let defaults = UserDefaults.standard
        if let savedURL = defaults.string(forKey: keyServerURL) {
            serverURL = savedURL
        }
        if let savedToken = defaults.string(forKey: keyApiToken) {
            apiToken = savedToken
        }
        if let savedLibId = defaults.string(forKey: keySelectedLibraryId) {
            selectedLibraryId = savedLibId
        }
    }

    private func saveSettings() {
        let defaults = UserDefaults.standard
        defaults.set(serverURL, forKey: keyServerURL)
        defaults.set(apiToken, forKey: keyApiToken)
        defaults.set(selectedLibraryId, forKey: keySelectedLibraryId)
    }
}

#Preview {
    ContentView()
}

