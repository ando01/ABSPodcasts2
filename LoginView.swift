import SwiftUI

struct LoginView: View {
    @EnvironmentObject var playerManager: PlayerManager

    @Binding var isConnected: Bool
    @Binding var client: ABSClient?

    @State private var serverURLString = ""
    @State private var apiToken = ""
    @State private var errorMessage: String?
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Audiobookshelf Server") {

                    TextField("Server URL", text: $serverURLString)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    SecureField("API Token", text: $apiToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Button {
                        Task { await connect() }
                    } label: {
                        if isLoading {
                            ProgressView()
                        } else {
                            Text("Connect")
                        }
                    }
                    .disabled(serverURLString.isEmpty || apiToken.isEmpty || isLoading)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("Connect")
        }
    }

    // MARK: - Connect
    private func connect() async {
        errorMessage = nil
        isLoading = true

        guard let url = URL(string: serverURLString) else {
            errorMessage = "Invalid server URL."
            isLoading = false
            return
        }

        let newClient = ABSClient(serverURL: url, apiToken: apiToken)
        client = newClient

        playerManager.serverURL = url
        playerManager.apiToken = apiToken

        do {
            let libs = try await newClient.fetchLibraries()

            await MainActor.run {
                playerManager.availableLibraries = libs   // 👈 REQUIRED for HomeView
                isConnected = true                        // 👈 triggers HomeView to appear
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
}

