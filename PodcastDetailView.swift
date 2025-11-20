import SwiftUI

struct PodcastDetailView: View {
    let podcast: ABSClient.LibraryItem
    let serverURL: String
    let apiToken: String

    @State private var episodes: [ABSClient.Episode] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil
    
    private let progressManager = PlaybackProgressManager.shared
    
    // Helper to build cover art URL
    private var podcastCoverURL: URL? {
        guard let base = URL(string: serverURL) else { return nil }
        return base.appending(path: "/api/items/\(podcast.id)/cover")
    }

    var body: some View {
        List {
            // Podcast header with cover art
            Section {
                HStack(spacing: 16) {
                    // Cover Art
                    if let artworkURL = podcastCoverURL {
                        AsyncImage(url: artworkURL) { phase in
                            switch phase {
                            case .empty:
                                ProgressView()
                                    .frame(width: 120, height: 120)
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 120, height: 120)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            case .failure:
                                placeholderArtwork
                            @unknown default:
                                placeholderArtwork
                            }
                        }
                    } else {
                        placeholderArtwork
                    }
                    
                    // Podcast Info
                    VStack(alignment: .leading, spacing: 8) {
                        Text(podcast.displayTitle)
                            .font(.title3)
                            .fontWeight(.semibold)
                            .lineLimit(3)
                        
                        let tags = podcast.displayTags
                        if !tags.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(tags, id: \.self) { tag in
                                        Text(tag)
                                            .font(.caption)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .fill(Color.blue.opacity(0.15))
                                            )
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
                
                // Description
                if let desc = podcast.displayDescription, !desc.isEmpty {
                    Text(desc)
                        .font(.subheadline)
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
                Section(header: Text("Episodes (\(episodes.count))")) {
                    ForEach(episodes) { episode in
                        NavigationLink(
                            destination: {
                                if let urlString = episode.enclosure?.url,
                                   let url = URL(string: urlString) {
                                    NowPlayingView(
                                        episode: episode,
                                        audioURL: url,
                                        artworkURL: podcastCoverURL,
                                        apiToken: apiToken
                                    )
                                } else {
                                    Text("No audio URL available for this episode.")
                                }
                            }
                        ) {
                            EpisodeRowView(
                                episode: episode,
                                artworkURL: podcastCoverURL,
                                progress: progressManager.loadProgress(for: episode.id)
                            )
                        }
                        .swipeActions(edge: .trailing) {
                            if progressManager.loadProgress(for: episode.id) != nil {
                                Button(role: .destructive) {
                                    progressManager.clearProgress(for: episode.id)
                                } label: {
                                    Label("Clear Progress", systemImage: "trash")
                                }
                            }
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
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadEpisodes()
        }
    }
    
    private var placeholderArtwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.2))
                .frame(width: 120, height: 120)
            Image(systemName: "music.note")
                .font(.system(size: 48))
                .foregroundStyle(.gray)
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

// MARK: - Episode Row Component

struct EpisodeRowView: View {
    let episode: ABSClient.Episode
    let artworkURL: URL?
    let progress: PlaybackProgressManager.Progress?
    
    var body: some View {
        HStack(spacing: 12) {
            // Episode artwork with progress overlay
            ZStack(alignment: .bottom) {
                if let artworkURL = artworkURL {
                    AsyncImage(url: artworkURL) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                                .frame(width: 50, height: 50)
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: 50, height: 50)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        case .failure:
                            smallPlaceholderArtwork
                        @unknown default:
                            smallPlaceholderArtwork
                        }
                    }
                } else {
                    smallPlaceholderArtwork
                }
                
                // Progress bar overlay
                if let progress = progress, !progress.isCompleted {
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(Color.blue)
                            .frame(width: geometry.size.width * (progress.progressPercentage / 100), height: 3)
                    }
                    .frame(height: 3)
                }
                
                // Completed checkmark
                if let progress = progress, progress.isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.white)
                        .background(
                            Circle()
                                .fill(Color.green)
                                .frame(width: 20, height: 20)
                        )
                        .offset(x: 15, y: 15)
                }
            }
            .frame(width: 50, height: 50)
            
            // Episode Info
            VStack(alignment: .leading, spacing: 4) {
                Text(episode.title)
                    .font(.body)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    if let date = episode.bestDate {
                        Text(date.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    if let progress = progress, !progress.isCompleted {
                        Text("• \(Int(progress.progressPercentage))% played")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                }

                if let desc = episode.description, !desc.isEmpty {
                    Text(desc)
                        .font(.caption)
                        .lineLimit(2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private var smallPlaceholderArtwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.gray.opacity(0.2))
                .frame(width: 50, height: 50)
            Image(systemName: "music.note")
                .font(.system(size: 20))
                .foregroundStyle(.gray)
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
