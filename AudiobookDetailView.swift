import SwiftUI

struct AudiobookDetailView: View {
    let audiobook: ABSClient.LibraryItem
    let serverURL: String
    let apiToken: String
    
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil
    @State private var audiobookData: AudiobookData?
    @State private var audioFileIno: String? = nil  // Store the file inode
    
    struct AudiobookData {
        let audioFiles: [AudioFile]
        let chapters: [Chapter]?
        
        struct AudioFile: Identifiable {
            let id: String
            let ino: String
            let filename: String
            let duration: TimeInterval
            let mimeType: String?
        }
        
        struct Chapter: Identifiable {
            let id: Int
            let title: String
            let start: TimeInterval
            let end: TimeInterval
        }
    }
    
    private var audiobookCoverURL: URL? {
        guard let base = URL(string: serverURL) else { return nil }
        return base.appending(path: "/api/items/\(audiobook.id)/cover")
    }
    
    private let progressManager = PlaybackProgressManager.shared
    
    var body: some View {
        List {
            // Audiobook header with cover art
            Section {
                HStack(spacing: 16) {
                    // Cover Art
                    if let artworkURL = audiobookCoverURL {
                        AsyncImage(url: artworkURL) { phase in
                            switch phase {
                            case .empty:
                                ProgressView()
                                    .frame(width: 140, height: 140)
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 140, height: 140)
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
                    
                    // Audiobook Info
                    VStack(alignment: .leading, spacing: 8) {
                        Text(audiobook.displayTitle)
                            .font(.title3)
                            .fontWeight(.semibold)
                            .lineLimit(3)
                        
                        if let author = audiobook.media?.metadata?.author {
                            Text(author)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        
                        let tags = audiobook.displayTags
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
                                                    .fill(Color.green.opacity(0.15))
                                            )
                                            .foregroundStyle(.green)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
                
                // Description
                if let desc = audiobook.displayDescription, !desc.isEmpty {
                    Text(desc)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                // Play entire audiobook button
                if let streamURL = audiobookStreamURL {
                    NavigationLink(destination: {
                        let audiobookEpisode = ABSClient.Episode(
                            id: audiobook.id,
                            title: audiobook.displayTitle,
                            description: audiobook.displayDescription,
                            pubDate: nil,
                            publishedAt: nil,
                            enclosure: ABSClient.Episode.Enclosure(
                                url: streamURL.absoluteString,
                                type: "audio/mpeg",
                                length: nil
                            )
                        )
                        NowPlayingView(
                            episode: audiobookEpisode,
                            audioURL: streamURL,
                            artworkURL: audiobookCoverURL,
                            apiToken: apiToken
                        )
                    }) {
                        HStack {
                            Image(systemName: "play.fill")
                            Text(hasProgress ? "Continue Audiobook" : "Play Audiobook")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundStyle(.white)
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                } else {
                    HStack {
                        if isLoading {
                            ProgressView()
                        }
                        Image(systemName: "play.fill")
                        Text("Loading...")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.gray)
                    .foregroundStyle(.white)
                    .cornerRadius(10)
                }
                
                // Progress indicator
                if let progress = progressManager.loadProgress(for: audiobook.id), !progress.isCompleted {
                    HStack {
                        Image(systemName: "clock")
                            .foregroundStyle(.secondary)
                        Text("\(Int(progress.progressPercentage))% complete • \(progressManager.formatTime(progress.currentTime)) of \(progressManager.formatTime(progress.duration))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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
                        Text("Loading audiobook details…")
                    }
                }
            }
            
            // Chapters/Audio Files section
            if let audiobookData = audiobookData {
                if let chapters = audiobookData.chapters, !chapters.isEmpty {
                    Section(header: Text("Chapters (\(chapters.count))")) {
                        ForEach(chapters) { chapter in
                            Button {
                                playFromChapter(chapter)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(chapter.title)
                                            .font(.body)
                                            .foregroundStyle(.primary)
                                        Text(progressManager.formatTime(chapter.start))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "play.circle")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                } else if !audiobookData.audioFiles.isEmpty {
                    Section(header: Text("Audio Files (\(audiobookData.audioFiles.count))")) {
                        ForEach(audiobookData.audioFiles) { file in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(file.filename)
                                    .font(.body)
                                Text(progressManager.formatTime(file.duration))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            
            // Metadata section
            Section(header: Text("Details")) {
                if let author = audiobook.media?.metadata?.author {
                    LabeledContent("Author", value: author)
                }
                
                if let releaseDate = audiobook.media?.metadata?.releaseDate {
                    LabeledContent("Release Date", value: releaseDate)
                }
                
                if let addedAt = audiobook.media?.metadata?.addedAt {
                    LabeledContent("Added", value: addedAt)
                }
            }
        }
        .navigationTitle("Audiobook")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadAudiobookDetails()
        }
    }
    
    private var placeholderArtwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.2))
                .frame(width: 140, height: 140)
            Image(systemName: "book.closed")
                .font(.system(size: 56))
                .foregroundStyle(.gray)
        }
    }
    
    // MARK: - Computed Properties
    
    private var hasProgress: Bool {
        progressManager.loadProgress(for: audiobook.id) != nil
    }
    
    private var audiobookStreamURL: URL? {
        guard let base = URL(string: serverURL) else { return nil }
        
        // If we have the file ino from API, use it
        if let ino = audioFileIno {
            var components = URLComponents(url: base.appending(path: "/api/items/\(audiobook.id)/file/\(ino)"), resolvingAgainstBaseURL: false)
            components?.queryItems = [
                URLQueryItem(name: "token", value: apiToken)
            ]
            let streamURL = components?.url
            print("🎵 Audiobook stream URL: \(streamURL?.absoluteString ?? "nil")")
            return streamURL
        }
        
        // Fallback: try the /s/book/ endpoint
        var components = URLComponents(url: base.appending(path: "/s/book/\(audiobook.id)"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "token", value: apiToken)
        ]
        let streamURL = components?.url
        print("🎵 Audiobook stream URL (fallback): \(streamURL?.absoluteString ?? "nil")")
        return streamURL
    }
    
    // MARK: - Actions
    
    private func playEntireAudiobook() {
        guard let streamURL = audiobookStreamURL else {
            errorMessage = "Cannot create audiobook stream URL"
            return
        }
        
        // Create a pseudo-episode for the audiobook to work with NowPlayingView
        let audiobookEpisode = ABSClient.Episode(
            id: audiobook.id,
            title: audiobook.displayTitle,
            description: audiobook.displayDescription,
            pubDate: nil,
            publishedAt: nil,
            enclosure: ABSClient.Episode.Enclosure(
                url: streamURL.absoluteString,
                type: "audio/mpeg",
                length: nil
            )
        )
        
        // Navigate to player - this will be handled by NavigationLink
        print("Playing audiobook: \(audiobook.displayTitle)")
    }
    
    private func playFromChapter(_ chapter: AudiobookData.Chapter) {
        // TODO: Implement chapter-specific playback
        // This would require modifying NowPlayingView to accept a start time
        print("Play from chapter: \(chapter.title) at \(chapter.start)s")
    }
    
    private func loadAudiobookDetails() {
        guard let url = URL(string: serverURL), !apiToken.isEmpty else {
            errorMessage = "Missing server URL or API token."
            return
        }
        
        let client = ABSClient(serverURL: url, apiToken: apiToken)
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                // Fetch the full audiobook details with expanded data
                var components = URLComponents(url: url.appending(path: "/api/items/\(audiobook.id)"), resolvingAgainstBaseURL: false)
                components?.queryItems = [
                    URLQueryItem(name: "expanded", value: "1")
                ]
                
                guard let detailURL = components?.url else {
                    throw ABSClient.ABSError.other(URLError(.badURL))
                }
                
                var request = URLRequest(url: detailURL)
                request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
                
                let (data, _) = try await URLSession.shared.data(for: request)
                
                // Parse the response to extract audio file info
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let media = json["media"] as? [String: Any],
                   let audioFiles = media["audioFiles"] as? [[String: Any]],
                   let firstFile = audioFiles.first,
                   let ino = firstFile["ino"] as? String {
                    
                    await MainActor.run {
                        self.audioFileIno = ino
                        print("✅ Found audio file ino: \(ino)")
                        
                        // Extract chapters if available
                        if let chapters = media["chapters"] as? [[String: Any]] {
                            var chapterList: [AudiobookData.Chapter] = []
                            for (index, chapterDict) in chapters.enumerated() {
                                if let start = chapterDict["start"] as? TimeInterval,
                                   let end = chapterDict["end"] as? TimeInterval,
                                   let title = chapterDict["title"] as? String {
                                    chapterList.append(AudiobookData.Chapter(
                                        id: index,
                                        title: title,
                                        start: start,
                                        end: end
                                    ))
                                }
                            }
                            
                            if !chapterList.isEmpty {
                                self.audiobookData = AudiobookData(
                                    audioFiles: [],
                                    chapters: chapterList
                                )
                                print("✅ Found \(chapterList.count) chapters")
                            }
                        }
                        
                        self.isLoading = false
                    }
                } else {
                    await MainActor.run {
                        self.isLoading = false
                    }
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
    AudiobookDetailView(
        audiobook: ABSClient.LibraryItem(
            id: "demo",
            libraryId: "lib1",
            mediaType: "book",
            media: .init(
                metadata: .init(
                    title: "The Great Gatsby",
                    subtitle: "A Novel",
                    description: "A classic American novel",
                    genres: ["Fiction", "Classics"],
                    author: "F. Scott Fitzgerald",
                    releaseDate: "1925",
                    publishedAt: nil,
                    addedAt: "2024-01-01"
                ),
                coverPath: nil,
                tags: ["Fiction"]
            ),
            tags: ["Fiction"]
        ),
        serverURL: "https://example.com",
        apiToken: "demo"
    )
}
