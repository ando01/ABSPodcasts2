import SwiftUI

struct LoginView: View {
    @Binding var isConnected: Bool
    @Binding var client: ABSClient?

    @State private var serverURLString: String = ""
    @State private var apiToken: String = ""

    @State private var username: String = ""
    @State private var password: String = ""

    @State private var loginMode: LoginMode = .apiToken
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?

    enum LoginMode: String, CaseIterable, Identifiable {
        case apiToken = "API Token"
        case credentials = "Username & Password"

        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    TextField("Server URL (e.g. https://abs.yourdomain.com)", text: $serverURLString)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                }

                Section("Login Method") {
                    Picker("Login Method", selection: $loginMode) {
                        ForEach(LoginMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if loginMode == .apiToken {
                    Section("API Token") {
                        SecureField("API Token", text: $apiToken)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                } else {
                    Section("Credentials") {
                        TextField("Username", text: $username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        SecureField("Password", text: $password)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                    }
                }

                Section {
                    Button {
                        Task { await connect() }
                    } label: {
                        if isLoading {
                            ProgressView()
                        } else {
                            Text("Connect")
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                    .disabled(isLoading || !canSubmit)
                }
            }
            .navigationTitle("Connect to Server")
        }
    }

    // MARK: - Helpers

    private var canSubmit: Bool {
        guard let _ = URL(string: serverURLString) else { return false }

        switch loginMode {
        case .apiToken:
            return !apiToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .credentials:
            return !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                   !password.isEmpty
        }
    }

    private func connect() async {
        guard let baseURL = URL(string: serverURLString) else {
            await MainActor.run {
                errorMessage = "Please enter a valid server URL."
            }
            return
        }

        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }

        do {
            let newClient: ABSClient

            switch loginMode {
            case .apiToken:
                // Just construct the client with the token
                newClient = ABSClient(serverURL: baseURL, apiToken: apiToken)

            case .credentials:
                // Call /api/login to get a token
                newClient = try await ABSClient.login(
                    serverURL: baseURL,
                    username: username,
                    password: password
                )
            }

            await MainActor.run {
                self.client = newClient
                self.isConnected = true
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                if let absError = error as? ABSClient.ABSError,
                   case .httpStatus(401) = absError {
                    self.errorMessage = "Invalid username or password."
                } else {
                    self.errorMessage = error.localizedDescription
                }
                self.isLoading = false
            }
        }
    }
}

