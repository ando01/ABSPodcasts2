import SwiftUI

struct HomeView: View {
    let client: ABSClient
    let onLogout: () -> Void

    @EnvironmentObject var playerManager: PlayerManager

    @State private var libraries: [ABSClient.Library] = []
    @State private var selectedLibrary: ABSClient.Library?
    @State private var items: [ABSClient.LibraryItem] = []

    @State private var isLoading = false
    @State private var errorMessage: String?

    // Recently added, sorted by best date
    private var sortedItems: [ABSClient.LibraryItem] {
        items.sorted { ($0.bestDate ?? .distantPast) > ($1.bestDate ?? .distantPast) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    // Library picker
                    if !libraries.isEmpty {
                        HStack {
                            Text("Podcasts")
                                .font(.headline)

                            Spacer()

                            Menu {
                                ForEach(libraries, id: \.id) { lib in
                                    Button(lib.name) {
                                        Task { await selectLibrary(lib) }
                                    }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Text(selectedLibrary?.name ?? "Select Library")
                                    Image(systemName: "chevron.down")
                                        .font(.caption)
                                }
                                .font(.subheadline)
                            }
                        }
                    }

                    // Continue Listening
                    continueListeningSection

                    // Recently Added
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recently Added")
                            .font(.headline)

                        if isLoading && items.isEmpty {
                            ProgressView("Loading…")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else if let errorMessage {
                            Text(errorMessage)
                                .foregroundColor(.red)
                        } else if sortedItems.isEmpty {
                            Text("No items in this library.")
                                .foregroundColor(.secondary)
                        } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 16) {
                                    ForEach(sortedItems, id: \.id) { item in
                                        NavigationLink {
                                            EpisodeListView(client: client, libraryItem: item)
                                        } label: {
                                            VStack(alignment: .leading, spacing: 6) {
                                                PodcastCoverView(client: client, item: item)
                                                    .frame(width: 140, height: 140)
                                                    .cornerRadius(14)

                                                Text(item.displayTitle)
                                                    .font(.caption)
                                                    .lineLimit(2)
                                            }
                                        }
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Home")
            .task {
                await loadLibrariesIfNeeded()
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Log Out") {
                        onLogout()
                    }
                }
            }
        }
    }

    // MARK: - Continue Listening card

    @ViewBuilder
    private var continueListeningSection: some View {
        if let show = playerManager.currentLibraryItem,
           let episode = playerManager.currentEpisode {

            VStack(alignment: .leading, spacing: 8) {
                Text("Continue Listening")
                    .font(.headline)

                Button {
                    playerManager.isPresented = true
                } label: {
                    HStack(spacing: 12) {
                        if let coverURL = URL.absCoverURL(
                            base: playerManager.serverURL,
                            itemId: show.id,
                            token: playerManager.apiToken,
                            width: 200
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
                            .frame(width: 60, height: 60)
                            .cornerRadius(10)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(episode.title)
                                .font(.subheadline)
                                .lineLimit(2)
                            Text("Tap player to view")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Image(systemName: playerManager.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title3)
                            .foregroundColor(.primary)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(.systemGray6))
                    )
                }
                .buttonStyle(.plain)
            }
        } else {
            // No active playback → nothing shown
            EmptyView()
        }
    }

    // MARK: - Loading

    private func loadLibrariesIfNeeded() async {
        guard libraries.isEmpty else { return }
        isLoading = true
        errorMessage = nil

        do {
            let libs = try await client.fetchLibraries()
            let podcastLibs = libs.filter { $0.mediaType.lowercased().contains("podcast") }
            let chosenList = podcastLibs.isEmpty ? libs : podcastLibs

            await MainActor.run {
                self.libraries = chosenList
            }

            if let first = chosenList.first {
                await selectLibrary(first)
            } else {
                await MainActor.run { self.isLoading = false }
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    private func selectLibrary(_ library: ABSClient.Library) async {
        await MainActor.run {
            selectedLibrary = library
            isLoading = true
            errorMessage = nil
            items = []
        }

        do {
            let fetched = try await client.fetchLibraryItems(libraryId: library.id)
            await MainActor.run {
                self.items = fetched
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

