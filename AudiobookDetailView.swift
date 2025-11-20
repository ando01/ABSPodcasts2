import SwiftUI

struct AudiobookDetailView: View {
    let audiobook: ABSClient.LibraryItem
    let serverURL: String
    let apiToken: String
    
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil
    @State private var audiobookData: AudiobookData?
    @State private var audioFileIno: String? = nil
    @State private var showPlayButton = false
    
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
    
    private var hasProgress: Bool {
        progressManager.loadProgress(for: audiobook.id) != nil
    }
    
    private var audiobookStreamURL: URL? {
        guard let base = URL(string: serverURL) else { return nil }
        
        if let ino = audioFileIno {
            var components = URLComponents(url: base.appending(path: "/api/items/\(audiobook.id)/file/\(ino)"), resolvingAgainstBaseURL: false)
            components?.queryItems = [URLQueryItem(name: "token", value: apiToken)]
            return components?.url
        }
        
        var components = URLComponents(url: base.appending(path: "/s/book/\(audiobook.id)"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "token", value: apiToken)]
        return components?.url
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 20) {
                    coverArtView
                    
                    titleView
                    
                    if let desc = audiobook.displayDescription, !desc.isEmpty {
                        Text(desc)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(5)
                    }
                    
                    playButtonView
                    
                    progressView
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }

            errorView
            
            chaptersView
            
            metadataView
        }
        .navigationTitle("Audiobook")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadAudiobookDetails()
        }
    }
    
    private var coverArtView: some View {
        Group {
            if let artworkURL = audiobookCoverURL {
                AsyncImage(url: artworkURL) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 180, height: 180)
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                            .shadow(radius: 10)
                    } else if phase.error != nil {
                        placeholderArtwork
                    } else {
                        ProgressView()
                            .frame(width: 180, height: 180)
                    }
                }
            } else {
                placeholderArtwork
            }
        }
    }
    
    private var titleView: some View {
        VStack(spacing: 8) {
            Text(audiobook.displayTitle)
                .font(.title2)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
            
            if let author = audiobook.media?.metadata?.author {
                Text("by \(author)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    @ViewBuilder
    private var playButtonView: some View {
        if let streamURL = audiobookStreamURL, showPlayButton {
            NavigationLink(destination: NowPlayingView(
                episode: ABSClient.Episode(
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
                ),
                audioURL: streamURL,
                artworkURL: audiobookCoverURL,
                apiToken: apiToken
            )) {
                HStack {
                    Image(systemName: "play.fill")
                    Text(hasProgress ? "Continue Listening" : "Start Listening")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.green)
                .foregroundStyle(.white)
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
        } else if isLoading {
            HStack {
                ProgressView()
                Text("Loading...")
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.gray)
            .foregroundStyle(.white)
            .cornerRadius(12)
        }
    }
    
    @ViewBuilder
    private var progressView: some View {
        if let progress = progressManager.loadProgress(for: audiobook.id), !progress.isCompleted {
            HStack {
                Image(systemName: "clock.fill")
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(Int(progress.progressPercentage))% complete")
                        .font(.caption)
                    Text("\(progressManager.formatTime(progress.currentTime)) of \(progressManager.formatTime(progress.duration))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(12)
            .background(Color.green.opacity(0.1))
            .cornerRadius(8)
        }
    }
    
    @ViewBuilder
    private var errorView: some View {
        if let errorMessage {
            Section(header: Text("Error")) {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }
        }
    }
    
    @ViewBuilder
    private var chaptersView: some View {
        if let chapters = audiobookData?.chapters, !chapters.isEmpty {
            Section(header: Text("Chapters (\(chapters.count))")) {
                ForEach(chapters) { chapter in
                    Button {
                        // TODO: Play from chapter
                    } label: {
                        HStack {
                            Text("\(chapter.id + 1)")
                                .font(.caption)
                                .fontWeight(.bold)
                                .frame(width: 30, height: 30)
                                .background(Circle().fill(Color.green.opacity(0.2)))
                                .foregroundStyle(.green)
                            
                            VStack(alignment: .leading) {
                                Text(chapter.title)
                                    .font(.body)
                                Text(progressManager.formatTime(chapter.start))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "play.circle")
                                .foregroundStyle(.green)
                        }
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var metadataView: some View {
        Section(header: Text("Details")) {
            if let author = audiobook.media?.metadata?.author {
                LabeledContent("Author", value: author)
            }
        }
    }
    
    private var placeholderArtwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.gray.opacity(0.2))
                .frame(width: 180, height: 180)
            Image(systemName: "book.closed")
                .font(.system(size: 72))
                .foregroundStyle(.gray)
        }
    }
    
    private func loadAudiobookDetails() {
        guard let url = URL(string: serverURL), !apiToken.isEmpty else {
            errorMessage = "Missing server URL or API token."
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                var components = URLComponents(url: url.appending(path: "/api/items/\(audiobook.id)"), resolvingAgainstBaseURL: false)
                components?.queryItems = [URLQueryItem(name: "expanded", value: "1")]
                
                guard let detailURL = components?.url else {
                    throw ABSClient.ABSError.other(URLError(.badURL))
                }
                
                var request = URLRequest(url: detailURL)
                request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
                
                let (data, _) = try await URLSession.shared.data(for: request)
                
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let media = json["media"] as? [String: Any],
                   let audioFiles = media["audioFiles"] as? [[String: Any]],
                   let firstFile = audioFiles.first,
                   let ino = firstFile["ino"] as? String {
                    
                    await MainActor.run {
                        self.audioFileIno = ino
                        
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
                                self.audiobookData = AudiobookData(audioFiles: [], chapters: chapterList)
                            }
                        }
                        
                        self.showPlayButton = true
                        self.isLoading = false
                    }
                } else {
                    await MainActor.run {
                        self.showPlayButton = true
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
