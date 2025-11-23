import SwiftUI

struct HomeView: View {
    let client: ABSClient
    @EnvironmentObject var playerManager: PlayerManager

    @State private var selectedLibrary: ABSClient.Library?
    @State private var isLoadingLibraries = true

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading) {

                // Library dropdown
                if !playerManager.availableLibraries.isEmpty {
                    Menu {
                        ForEach(playerManager.availableLibraries) { lib in
                            Button(lib.name) { selectedLibrary = lib }
                        }
                    } label: {
                        HStack {
                            Text(selectedLibrary?.name ?? "Select Library")
                                .font(.title2).bold()
                            Image(systemName: "chevron.down")
                        }
                    }
                    .padding(.horizontal)
                }

                // Main content
                if let selectedLibrary {
                    LibraryDetailView(client: client, library: selectedLibrary)
                } else {
                    Text("Select a library to begin.")
                        .padding()
                }

                Spacer()
            }
            .task { await loadLibraries() }
            .navigationTitle("Home")
        }
    }

    private func loadLibraries() async {
        do {
            let libs = try await client.fetchLibraries()
            await MainActor.run {
                playerManager.availableLibraries = libs
                selectedLibrary = libs.first
                isLoadingLibraries = false
            }
        } catch {
            print("Failed to load libraries:", error)
        }
    }
}

