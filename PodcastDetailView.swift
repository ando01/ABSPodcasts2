import SwiftUI

struct PodcastDetailView: View {
    let podcast: ABSClient.LibraryItem
    let serverURL: String
    let apiToken: String

    @EnvironmentObject var playerManager: PlayerManager

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
                            .multilineTextAlignment(.leading)
                            .lineLimit(6)
                            .padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 12)
            }
            
            // Loading state with skeletons
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
                        Button {
                            if let urlString = episode.enclosure?.url,
                               let url = URL(string: urlString) {
                                playerManager.start(
                                    episode: episode,
                                    audioURL: url,
                                    artworkURL: podcastCoverURL
                                )
                            }
                        } label: {
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
                        .animation(
                            .spring(response: 0.4, dampingFraction: 0.8)
                                .delay(Double(index) * 0.03),
                            value: episodes.count
                        )
                    }
                }
            }
            // Empty state
            else {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "waveform.circle")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("No episodes yet")
                            .font(.headline)
                        Text("Pull down to refresh or check back later.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                }
            }
            
            // Error section if needed
            if let errorMessage = errorMessage {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        Text(errorMessage)
                            .font(.subheadline)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(podcast.displayTitle)
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
    
    // MARK: - Episode Loading
    
    private func loadEpisodes() {
        guard let url = URL(string: serverURL), !apiToken.isEmpty else {
            errorMessage = "Missing server URL or API token."
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        Task {
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
                        self.isLoading = false
                    }
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.errorMessage = error.localizedDescription
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
                                .transition(.opacity.combined(with: .scale))
                        case .failure:
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.gray.opacity(0.2))
                                .frame(width: 56, height: 56)
                                .overlay(
                                    Image(systemName: "waveform")
                                        .foregroundStyle(.gray)
                                )
                        @unknown default:
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.gray.opacity(0.2))
                                .frame(width: 56, height: 56)
                        }
                    }
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 56, height: 56)
                        .overlay(
                            Image(systemName: "waveform")
                                .foregroundStyle(.gray)
                        )
                }
                
                // Progress bar
                if let progress = progress, progress.progressPercentage > 0 {
                    GeometryReader { geo in
                        let width = geo.size.width * CGFloat(min(progress.progressPercentage / 100.0, 1.0))
                        Rectangle()
                            .fill(Color.blue)
                            .frame(width: width, height: 4)
                            .cornerRadius(2)
                            .offset(y: -2)
                    }
                    .frame(height: 4)
                }
            }
            .frame(width: 56, height: 56)
            
            // Title & meta
            VStack(alignment: .leading, spacing: 4) {
                Text(episode.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)
                
                if let date = episode.bestDate {
                    Text(date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                if let progress = progress, progress.progressPercentage > 0 {
                    Text(progress.progressPercentage >= 95 ? "Finished" : "Progress: \(Int(progress.progressPercentage))%")
                        .font(.caption2)
                        .foregroundStyle(progress.progressPercentage >= 95 ? .green : .blue)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Skeleton Row for Loading

struct SkeletonEpisodeRow: View {
    @State private var isAnimating = false
    
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8)
                .fill(LinearGradient(
                    colors: [
                        Color.gray.opacity(0.2),
                        Color.gray.opacity(0.3),
                        Color.gray.opacity(0.2)
                    ],
                    startPoint: isAnimating ? .leading : .trailing,
                    endPoint: isAnimating ? .trailing : .leading
                ))
                .frame(width: 56, height: 56)
                .animation(.linear(duration: 1.2).repeatForever(autoreverses: true), value: isAnimating)
            
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.25))
                    .frame(height: 14)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 10)
                    .padding(.trailing, 40)
            }
        }
        .redacted(reason: .placeholder)
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
    .environmentObject(PlayerManager())
}

