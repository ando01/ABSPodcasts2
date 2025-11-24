import SwiftUI

struct HomeView: View {
    let client: ABSClient

    @EnvironmentObject var playerManager: PlayerManager

    @State private var libraries: [ABSClient.Library] = []
    @State private var isLoadingLibraries = true
    @State private var librariesError: String?

    @State private var selectedLibrary: ABSClient.Library?
    @State private var recentItems: [ABSClient.LibraryItem] = []
    @State private var isLoadingRecent = false
    @State private var itemsError: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {

                        // MARK: Library picker row (top)
                        HStack {
                            if let selectedLibrary {
                                Menu {
                                    ForEach(libraries, id: \.id) { lib in
                                        Button(lib.name) {
                                            self.selectedLibrary = lib
                                            Task { await loadRecentItems() }
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Text(selectedLibrary.name)
                                            .font(.title3)
                                            .bold()
                                        Image(systemName: "chevron.down")
                                            .font(.caption)
                                    }
                                    .foregroundStyle(.blue)
                                }
                            } else {
                                Text("Loading libraries…")
                                    .font(.title3)
                                    .bold()
                            }

                            Spacer()
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)

                        if let librariesError {
                            Text(librariesError)
                                .foregroundStyle(.red)
                                .padding(.horizontal)
                        }

                        // MARK: Continue Listening
                        continueListeningSection

                        // MARK: Recently Added
                        recentlyAddedSection

                        Spacer(minLength: 40)
                    }
                }
            }
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await loadLibrariesIfNeeded()
            }
        }
    }

    // MARK: - Continue Listening

    private var continueListeningSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Continue Listening")
                .font(.headline)
                .padding(.horizontal)

            if let show = playerManager.currentLibraryItem,
               let episode = playerManager.currentEpisode {

                HStack(spacing: 12) {
                    // Cover art
                    if let coverURL = URL.absCoverURL(
                        base: client.serverURL,
                        itemId: show.id,
                        token: client.apiToken,
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
                        .frame(width: 56, height: 56)
                        .cornerRadius(8)
                    }

                    // Title + hint
                    VStack(alignment: .leading, spacing: 4) {
                        Text(episode.title)
                            .font(.subheadline)
                            .lineLimit(2)
                        Text(playerManager.isPlaying ? "Tap player to view" : "Tap to resume")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // Play/Pause button that actually controls playback
                    Button {
                        toggleContinuePlayback(show: show, episode: episode)
                    } label: {
                        Image(systemName: playerManager.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title2)
                            .padding(8)
                            .background(
                                Circle()
                                    .fill(Color.blue.opacity(0.12))
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(.systemGray6))
                )
                .padding(.horizontal)
                .contentShape(Rectangle())
                .onTapGesture {
                    // Tapping the card opens the full Now Playing sheet
                    playerManager.isPresented = true
                }

            } else {
                Text("Nothing to resume yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }
        }
    }

    /// Actually handle play/pause from the Continue Listening card.
    /// - If something is already playing, this will pause.
    /// - If paused (or not started), this will start/resume the current episode.
    private func toggleContinuePlayback(show: ABSClient.LibraryItem, episode: ABSClient.Episode) {
        // If the current item is already playing, pause it.
        if playerManager.isPlaying {
            // Assumes PlayerManager has a pause() method.
            // If this does not exist, we can adjust to your actual API.
            playerManager.pause()
            return
        }

        // Not playing: (re)start playback for this episode
        guard let urlString = episode.enclosure?.url,
              let url = URL(string: urlString) else {
            return
        }

        // Use the same pattern as PodcastDetailView
        let artworkURL = URL.absCoverURL(
            base: client.serverURL,
            itemId: show.id,
            token: client.apiToken,
            width: 400
        )

        playerManager.start(
            libraryItem: show,
            episode: episode,
            audioURL: url,
            artworkURL: artworkURL
        )
    }

    // MARK: - Recently Added

    private var recentlyAddedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recently Added")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal)

            if let itemsError {
                Text(itemsError)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            } else if isLoadingRecent {
                ProgressView()
                    .padding(.horizontal)
            } else if recentItems.isEmpty {
                Text("No items found.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(recentItems, id: \.id) { item in
                            NavigationLink {
                                destinationView(for: item)
                            } label: {
                                recentItemCard(for: item)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }

    private func recentItemCard(for item: ABSClient.LibraryItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray5))
                    .frame(width: 140, height: 140)

                if let coverURL = URL.absCoverURL(
                    base: client.serverURL,
                    itemId: item.id,
                    token: client.apiToken,
                    width: 300
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
                    .frame(width: 140, height: 140)
                    .clipped()
                    .cornerRadius(12)
                }
            }

            Text(item.displayTitle)
                .font(.caption)
                .lineLimit(2)
                .frame(width: 140, alignment: .leading)
        }
    }

    // MARK: - Routing

    @ViewBuilder
    private func destinationView(for item: ABSClient.LibraryItem) -> some View {
        if item.mediaType?.lowercased() == "book" {
            AudiobookDetailView(item: item, client: client)
        } else {
            EpisodeListView(client: client, libraryItem: item)
        }
    }

    // MARK: - Loading

    private func loadLibrariesIfNeeded() async {
        guard isLoadingLibraries else { return }

        do {
            let libs = try await client.fetchLibraries()
            await MainActor.run {
                self.libraries = libs
                self.isLoadingLibraries = false

                // Default to podcasts if available, else first library
                if let podcastLib = libs.first(where: { $0.mediaType.lowercased() == "podcast" }) {
                    self.selectedLibrary = podcastLib
                } else {
                    self.selectedLibrary = libs.first
                }
            }

            await loadRecentItems()
        } catch {
            await MainActor.run {
                self.librariesError = error.localizedDescription
                self.isLoadingLibraries = false
            }
        }
    }

    private func loadRecentItems() async {
        guard let library = selectedLibrary else {
            await MainActor.run {
                self.recentItems = []
            }
            return
        }

        await MainActor.run {
            self.isLoadingRecent = true
            self.itemsError = nil
        }

        do {
            let items = try await client.fetchLibraryItems(libraryId: library.id)
            let sorted = items.sorted { (a, b) in
                (a.bestDate ?? .distantPast) > (b.bestDate ?? .distantPast)
            }
            await MainActor.run {
                self.recentItems = Array(sorted.prefix(20))
                self.isLoadingRecent = false
            }
        } catch {
            await MainActor.run {
                self.itemsError = error.localizedDescription
                self.isLoadingRecent = false
            }
        }
    }
}

