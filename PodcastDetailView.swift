import SwiftUI

struct PodcastDetailView: View {
    let podcast: ABSClient.LibraryItem
    let serverURL: String
    let apiToken: String

    @State private var episodes: [ABSClient.Episode] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil

    var body: some View {
        List {
            // Podcast header
            Section {
                Text(podcast.displayTitle)
                    .font(.title2)
                    .fontWeight(.semibold)

                if let desc = podcast.displayDescription, !desc.isEmpty {
                    Text(desc)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                let tags = podcast.displayTags
                if !tags.isEmpty {
                    Text(tags.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Error
            if let errorMessage {
                Section(header: Text("Error")) {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.subheadline)
                }
            }

            // Loading
            if isLoading {
                Section {
                    HStack {
                        ProgressView()
                        Text("Loading episodes…")
                    }
                }
            }
            // Episodes
            else if !episodes.isEmpty {
                Section(header: Text("Episodes")) {
                    ForEach(episodes) { episode in
                        NavigationLink(
                            destination: {
                                if let urlString = episode.enclosure?.url,
                                   let url = URL(string: urlString) {
                                    // Build artwork URL from ABS cover endpoint
                                    let artworkURL: URL? = {
                                        guard let base = URL(string: serverURL) else { return nil }
                                        return base.appending(path: "/api/items/\(podcast.id)/cover")
                                    }()
                                    NowPlayingView(
                                        episode: episode,
                                        audioURL: url,
                                        artworkURL: artworkURL
                                    )
                                } else {
                                    Text("No audio URL available for this episode.")
                                }
                            }
                        ) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(episode.title)
                                    .font(.body)

                                if let date = episode.bestDate {
                                    Text(date.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                if let desc = episode.description, !desc.isEmpty {
                                    Text(desc)
                                        .font(.caption)
                                        .lineLimit(2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            // No episodes
            else {
                Section {
                    Text("No episodes found.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Episodes")
        .onAppear {
            loadEpisodes()
        }
    }

    // MARK: - Loading

    private func loadEpisodes() {
        guard let url = URL(string: serverURL), !apiToken.isEmpty else {
            errorMessage = "Missing server URL or API token."
            return
        }

        let client = ABSClient(serverURL: url, apiToken: apiToken)
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let fetched = try await client.fetchEpisodes(podcastItemId: podcast.id)

                // Sort newest → oldest using bestDate
                let sorted = fetched.sorted { a, b in
                    let da = a.bestDate ?? .distantPast
                    let db = b.bestDate ?? .distantPast
                    return da > db
                }

                await MainActor.run {
                    self.episodes = sorted
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    if let absErr = error as? ABSClient.ABSError {
                        errorMessage = absErr.localizedDescription
                    } else {
                        errorMessage = error.localizedDescription
                    }
                    isLoading = false
                }
            }
        }
    }
}

#Preview {
    PodcastDetailView(
        podcast: ABSClient.LibraryItem(
            id: "demo",
            libraryId: "lib1",
            mediaType: "podcast",
            media: .init(
                metadata: .init(
                    title: "Demo Podcast",
                    subtitle: nil,
                    description: "A demo show",
                    genres: ["Tech"],
                    author: "Me",
                    releaseDate: nil,
                    publishedAt: nil,
                    addedAt: nil
                ),
                coverPath: nil,
                tags: ["Tech"]
            ),
            tags: ["Tech"]
        ),
        serverURL: "https://example.com",
        apiToken: "demo"
    )
}

