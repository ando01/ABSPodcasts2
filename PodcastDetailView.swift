import SwiftUI

struct PodcastDetailView: View {
    let podcast: ABSClient.LibraryItem
    let serverURL: String
    let apiToken: String

    @State private var episodes: [ABSClient.Episode] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil
    
    private let progressManager = PlaybackProgressManager.shared
    
    private var podcastCoverURL: URL? {
        guard let base = URL(string: serverURL) else { return nil }
        return base.appending(path: "/api/items/\(podcast.id)/cover")
    }

    var body: some View {
        List {
            // Podcast header with enhanced design
            Section {
                VStack(spacing: 16) {
                    // Cover art with shadow and animation
                    if let artworkURL = podcastCoverURL {
                        AsyncImage(url: artworkURL) { phase in
                            switch phase {
                            case .empty:
                                ZStack {
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(Color.gray.opacity(0.2))
                                        .frame(width: 160, height: 160)
                                    ProgressView()
                                }
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 160, height: 160)
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                                    .shadow(color: .black.opacity(0.2), radius: 12, x: 0, y: 6)
                                    .transition(.scale.combined(with: .opacity))
                            case .failure:
                                placeholderArtwork
                            @unknown default:
                                placeholderArtwork
                            }
                        }
                    } else {
                        placeholderArtwork
                    }
                    
                    // Title and info
                    VStack(spacing: 8) {
                        Text(podcast.displayTitle)
                            .font(.title2)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                        
                        if !episodes.isEmpty {
                            Text("\(episodes.count) Episodes")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        
                        // Tags
                        let tags = podcast.displayTags
                        if !tags.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(tags, id: \.self) { tag in
                                        Text(tag)
                                            .font(.caption)
                                            .fontWeight(.medium)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(
                                                Capsule()
                                                    .fill(Color.blue.opacity(0.15))
                                            )
                                            .foregroundStyle(.blue)
                                    }
                                }
                            }
                        }
                    }
                    
                    // Description
                    if let desc = podcast.displayDescription, !desc.isEmpty {
                        Text(desc)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(4)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            // Error with animation
            if let errorMessage {
                Section(header: Text("Error")) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.subheadline)
                    }
                }
                .transition(.opacity.combined(with: .scale))
            }

            // Loading skeleton
            if isLoading {
                Section(header: Text("Episodes")) {
                    ForEach(0..<5, id: \.self) { _ in
                        SkeletonEpisodeRow()
                    }
                }
            }
            // Episodes with staggered animation
            else if !episodes.isEmpty {
                Section(header: HStack {
                    Text("Episodes")
                        .font(.headline)
                    Spacer()
                }) {
                    ForEach(Array(episodes.enumerated()), id: \.element.id) { index, episode in
                        NavigationLink(
                            destination: {
                                if let urlString = episode.enclosure?.url,
                                   let url = URL(string: urlString) {
                                    NowPlayingView(
                                        episode: episode,
                                        audioURL: url,
                                        artworkURL: podcastCoverURL,
                                        apiToken: nil
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
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                        .swipeActions(edge: .trailing) {
                            if progressManager.loadProgress(for: episode.id) != nil {
                                Button(role: .destructive) {
                                    withAnimation {
                                        progressManager.clearProgress(for: episode.id)
                                    }
                                } label: {
                                    Label("Clear Progress", systemImage: "trash")
                                }
                            }
                        }
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .offset(y: 10)),
                            removal: .opacity
                        ))
                        .animation(.spring(response: 0.4, dampingFraction: 0.8).delay(Double(index) * 0.03), value: episodes.count)
                    }
                }
            }
            // Empty state
            else {
                Section {
                    VStack(spacing: 16) {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 48))
                            .foregroundStyle(.gray.opacity(0.5))
                        
                        Text("No episodes found")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }
            }
        }
        .navigationTitle("Episodes")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadEpisodes()
        }
        .refreshable {
            await refreshEpisodes()
        }
    }
    
    private var placeholderArtwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.gray.opacity(0.2))
                .frame(width: 160, height: 160)
            Image(systemName: "music.note")
                .font(.system(size: 64))
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

                let sorted = fetched.sorted { a, b in
                    let da = a.bestDate ?? .distantPast
                    let db = b.bestDate ?? .distantPast
                    return da > db
                }

                await MainActor.run {
                    withAnimation(.spring(response: 0.4)) {
                        self.episodes = sorted
                        self.isLoading = false
                    }
                }
            } catch {
                await MainActor.run {
                    withAnimation {
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
    
    private func refreshEpisodes() async {
        guard let url = URL(string: serverURL), !apiToken.isEmpty else { return }
        let client = ABSClient(serverURL: url, apiToken: apiToken)
        
        do {
            let fetched = try await client.fetchEpisodes(podcastItemId: podcast.id)
            let sorted = fetched.sorted { a, b in
                let da = a.bestDate ?? .distantPast
                let db = b.bestDate ?? .distantPast
                return da > db
            }
            
            await MainActor.run {
                withAnimation(.spring(response: 0.4)) {
                    self.episodes = sorted
                }
            }
        } catch {
            // Silently fail on refresh
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
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.gray.opacity(0.2))
                                    .frame(width: 56, height: 56)
                                ProgressView()
                                    .scaleEffect(0.7)
                            }
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: 56, height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .transition(.scale.combined(with: .opacity))
                        case .failure:
                            smallPlaceholderArtwork
                        @unknown default:
                            smallPlaceholderArtwork
                        }
                    }
                } else {
                    smallPlaceholderArtwork
                }
                
                // Progress bar overlay with animation
                if let progress = progress, !progress.isCompleted {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color.black.opacity(0.3))
                            
                            Rectangle()
                                .fill(Color.blue)
                                .frame(width: geometry.size.width * (progress.progressPercentage / 100))
                        }
                    }
                    .frame(height: 3)
                    .clipShape(RoundedRectangle(cornerRadius: 1.5))
                    .transition(.opacity)
                }
                
                // Completed checkmark with bounce animation
                if let progress = progress, progress.isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.white)
                        .background(
                            Circle()
                                .fill(Color.green)
                                .frame(width: 24, height: 24)
                        )
                        .offset(x: 16, y: 16)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: 56, height: 56)
            
            // Episode Info
            VStack(alignment: .leading, spacing: 4) {
                Text(episode.title)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    if let date = episode.bestDate {
                        Text(date.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    if let progress = progress, !progress.isCompleted {
                        Text("•")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Text("\(Int(progress.progressPercentage))%")
                            .font(.caption)
                            .foregroundStyle(.blue)
                            .fontWeight(.medium)
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
        .padding(.vertical, 6)
    }
    
    private var smallPlaceholderArtwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.2))
                .frame(width: 56, height: 56)
            Image(systemName: "music.note")
                .font(.system(size: 22))
                .foregroundStyle(.gray)
        }
    }
}

// MARK: - Skeleton Episode Row

struct SkeletonEpisodeRow: View {
    @State private var isAnimating = false
    
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.2))
                .frame(width: 56, height: 56)
            
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 16)
                    .frame(maxWidth: .infinity)
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 12)
                    .frame(width: 100)
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 12)
                    .frame(maxWidth: 200)
            }
        }
        .padding(.vertical, 6)
        .opacity(isAnimating ? 0.5 : 1.0)
        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isAnimating)
        .onAppear {
            isAnimating = true
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
