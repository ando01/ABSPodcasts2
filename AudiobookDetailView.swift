import SwiftUI

struct AudiobookDetailView: View {
    let audiobook: ABSClient.LibraryItem
    let serverURL: String
    let apiToken: String
    
    @EnvironmentObject var playerManager: PlayerManager

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
        }
    }
    
    private let progressManager = PlaybackProgressManager.shared
    
    private var audiobookCoverURL: URL? {
        guard let base = URL(string: serverURL) else { return nil }
        return base.appending(path: "/api/items/\(audiobook.id)/cover")
    }
    
    private var audiobookStreamURL: URL? {
        guard let base = URL(string: serverURL) else { return nil }
        
        if let ino = audioFileIno {
            var components = URLComponents(
                url: base.appending(path: "/s/book/\(audiobook.id)/file/\(ino)"),
                resolvingAgainstBaseURL: false
            )
            components?.queryItems = [URLQueryItem(name: "token", value: apiToken)]
            return components?.url
        }
        
        var components = URLComponents(
            url: base.appending(path: "/s/book/\(audiobook.id)"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "token", value: apiToken)]
        return components?.url
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 16) {
                    coverArtView
                    titleView
                    
                    if let description = audiobook.displayDescription, !description.isEmpty {
                        Text(description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(6)
                    }
                    
                    playButtonView
                    
                    if let progress = progressManager.loadProgress(for: audiobook.id) {
                        progressSummaryView(progress: progress)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            
            if let chapters = audiobookData?.chapters, !chapters.isEmpty {
                Section(header: Text("Chapters")) {
                    ForEach(chapters) { chapter in
                        Button {
                            // TODO: Implement “play from chapter start”
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
            
            if let audiobookData = audiobookData {
                Section(header: Text("Files")) {
                    ForEach(audiobookData.audioFiles) { file in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(file.filename)
                                    .font(.subheadline)
                                if let mimeType = file.mimeType {
                                    Text(mimeType)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(progressManager.formatTime(file.duration))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            
            if let errorMessage = errorMessage {
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        Text(errorMessage)
                            .font(.subheadline)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(audiobook.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadAudiobookDetails()
        }
    }
    
    // MARK: - Subviews
    
    private var coverArtView: some View {
        Group {
            if let url = audiobookCoverURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .frame(width: 180, height: 180)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 180, height: 180)
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                            .shadow(radius: 10)
                    case .failure:
                        placeholderArtwork
                    @unknown default:
                        placeholderArtwork
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
    
    private var hasProgress: Bool {
        progressManager.loadProgress(for: audiobook.id) != nil
    }
    
    // 👇 FIXED: ViewBuilder + final else -> EmptyView
    @ViewBuilder
    private var playButtonView: some View {
        if let streamURL = audiobookStreamURL, showPlayButton {
            Button {
                let episode = ABSClient.Episode(
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
                
                playerManager.start(
                    episode: episode,
                    audioURL: streamURL,
                    artworkURL: audiobookCoverURL
                )
            } label: {
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
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private func progressSummaryView(progress: PlaybackProgressManager.Progress) -> some View {
        VStack(alignment: .leading, spacing: 8) {
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
            
            if progress.isCompleted {
                Text("You’ve finished this audiobook.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private var placeholderArtwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.gray.opacity(0.2))
                .frame(width: 180, height: 180)
            Image(systemName: "book.closed")
                .font(.system(size: 64))
                .foregroundStyle(.gray)
        }
    }
    
    // MARK: - Networking
    
    private func loadAudiobookDetails() {
        guard let url = URL(string: serverURL), !apiToken.isEmpty else {
            errorMessage = "Missing server URL or API token."
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                var request = URLRequest(url: url.appending(path: "/api/items/\(audiobook.id)"))
                request.httpMethod = "GET"
                request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
                
                let (data, response) = try await URLSession.shared.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse,
                      200..<300 ~= httpResponse.statusCode else {
                    throw ABSClient.ABSError.invalidResponse
                }
                
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                
                struct ItemResponse: Decodable {
                    struct Media: Decodable {
                        struct Chapter: Decodable {
                            let title: String
                            let start: TimeInterval
                        }
                        struct AudioFile: Decodable {
                            let ino: String
                            let filename: String
                            let duration: TimeInterval
                            let mimeType: String?
                        }
                        let audioFiles: [AudioFile]?
                        let chapters: [Chapter]?
                    }
                    let media: Media?
                }
                
                let itemResponse = try decoder.decode(ItemResponse.self, from: data)
                
                var audioFileList: [AudiobookData.AudioFile] = []
                var chapterList: [AudiobookData.Chapter] = []
                
                if let media = itemResponse.media {
                    if let files = media.audioFiles {
                        audioFileList = files.enumerated().map { index, file in
                            AudiobookData.AudioFile(
                                id: "\(index)",
                                ino: file.ino,
                                filename: file.filename,
                                duration: file.duration,
                                mimeType: file.mimeType
                            )
                        }
                    }
                    
                    if let chapters = media.chapters {
                        chapterList = chapters.enumerated().map { index, chapter in
                            AudiobookData.Chapter(
                                id: index,
                                title: chapter.title,
                                start: chapter.start
                            )
                        }
                    }
                }
                
                await MainActor.run {
                    if !audioFileList.isEmpty || !chapterList.isEmpty {
                        self.audiobookData = AudiobookData(audioFiles: audioFileList, chapters: chapterList)
                        self.audioFileIno = audioFileList.first?.ino
                    }
                    self.showPlayButton = true
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    if let absError = error as? ABSClient.ABSError {
                        errorMessage = absError.localizedDescription
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
    .environmentObject(PlayerManager())
}

