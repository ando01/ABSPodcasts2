import SwiftUI

struct AudiobookDetailView: View {
    // MARK: - Inputs

    let audiobook: ABSClient.LibraryItem
    let serverURL: String
    let apiToken: String

    // MARK: - Environment

    @EnvironmentObject var playerManager: PlayerManager
    @EnvironmentObject var playbackSettings: PlaybackSettingsViewModel

    // MARK: - State

    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var audiobookData: AudiobookData?
    /// Path like "/s/item/li_.../Some File.mp3" from the first track
    @State private var primaryTrackPath: String?

    // Local model for chapters / tracks if you want to show them later
    struct AudiobookData {
        struct Chapter: Identifiable {
            let id: Int
            let title: String
            let start: TimeInterval
            let end: TimeInterval
        }

        struct Track: Identifiable {
            let id: Int
            let title: String
            let duration: TimeInterval
            let startOffset: TimeInterval
            let contentUrl: String
        }

        let chapters: [Chapter]
        let tracks: [Track]
    }

    private let progressManager = PlaybackProgressManager.shared

    // MARK: - Computed URLs

    private var coverURL: URL? {
        guard let base = URL(string: serverURL) else { return nil }
        var comps = URLComponents(
            url: base.appendingPathComponent("/api/items/\(audiobook.id)/cover"),
            resolvingAgainstBaseURL: false
        )
        if !apiToken.isEmpty {
            comps?.queryItems = [URLQueryItem(name: "token", value: apiToken)]
        }
        return comps?.url
    }

    /// Final stream URL that AVPlayer should use
    private var audiobookStreamURL: URL? {
        guard let base = URL(string: serverURL),
              let path = primaryTrackPath else {
            return nil
        }

        var comps = URLComponents()
        comps.scheme = base.scheme
        comps.host = base.host
        comps.port = base.port
        comps.path = path

        if !apiToken.isEmpty {
            comps.queryItems = [URLQueryItem(name: "token", value: apiToken)]
        }

        let url = comps.url
        print("🎧 Audiobook stream URL: \(url?.absoluteString ?? "nil")")
        return url
    }

    private var hasProgress: Bool {
        progressManager.loadProgress(for: audiobook.id) != nil
    }

    // MARK: - Body

    var body: some View {
        List {
            headerSection

            if let errorMessage {
                Section("Error") {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.subheadline)
                }
            }

            if isLoading {
                Section {
                    HStack {
                        ProgressView()
                        Text("Loading audiobook details…")
                    }
                }
            }

            if let data = audiobookData, !data.chapters.isEmpty {
                Section("Chapters (\(data.chapters.count))") {
                    ForEach(data.chapters) { chapter in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(chapter.title)
                                .font(.body)
                            Text(progressManager.formatTime(chapter.start))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            detailsSection
        }
        .navigationTitle("Audiobook")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadAudiobookDetails)
    }

    // MARK: - Sections

    private var headerSection: some View {
        Section {
            HStack(spacing: 16) {
                // Artwork
                if let url = coverURL {
                    AsyncImage(url: url) { phase in
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

                // Basic info
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

            if let desc = audiobook.displayDescription, !desc.isEmpty {
                Text(desc)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Play button
            playButton
                .padding(.top, 8)

            // Progress
            if let progress = progressManager.loadProgress(for: audiobook.id),
               !progress.isCompleted {
                HStack {
                    Image(systemName: "clock")
                        .foregroundStyle(.secondary)
                    Text(
                        "\(Int(progress.progressPercentage))% complete • " +
                        "\(progressManager.formatTime(progress.currentTime)) of " +
                        "\(progressManager.formatTime(progress.duration))"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var playButton: some View {
        Button {
            startPlayback()
        } label: {
            HStack {
                Image(systemName: "play.fill")
                Text(hasProgress ? "Continue Audiobook" : "Play Audiobook")
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(audiobookStreamURL == nil ? Color.gray : Color.blue)
            .foregroundStyle(.white)
            .cornerRadius(10)
        }
        .disabled(audiobookStreamURL == nil)
        .buttonStyle(.plain)
    }

    private var detailsSection: some View {
        Section("Details") {
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

    // MARK: - Actions

    private func startPlayback() {
        guard let url = audiobookStreamURL else {
            errorMessage = "Cannot determine audiobook stream URL."
            return
        }

        // Wrap audiobook as an Episode so NowPlayingView can reuse the same model.
        let pseudoEpisode = ABSClient.Episode(
            id: audiobook.id,
            title: audiobook.displayTitle,
            description: audiobook.displayDescription,
            pubDate: nil,
            publishedAt: nil,
            enclosure: ABSClient.Episode.Enclosure(
                url: url.absoluteString,
                type: "audio/mpeg",
                length: nil
            )
        )

        playerManager.start(
            episode: pseudoEpisode,
            audioURL: url,
            artworkURL: coverURL
        )
    }

    private func loadAudiobookDetails() {
        guard let base = URL(string: serverURL), !apiToken.isEmpty else {
            errorMessage = "Missing server URL or API token."
            return
        }

        isLoading = true
        errorMessage = nil

        Task {
            do {
                var comps = URLComponents(
                    url: base.appendingPathComponent("/api/items/\(audiobook.id)"),
                    resolvingAgainstBaseURL: false
                )
                comps?.queryItems = [URLQueryItem(name: "expanded", value: "1")]

                guard let detailURL = comps?.url else {
                    throw URLError(.badURL)
                }

                var req = URLRequest(url: detailURL)
                req.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")

                let (data, _) = try await URLSession.shared.data(for: req)

                guard
                    let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let media = root["media"] as? [String: Any]
                else {
                    throw URLError(.cannotParseResponse)
                }

                var chapters: [AudiobookData.Chapter] = []
                var tracks: [AudiobookData.Track] = []
                var firstTrackPath: String?

                if let chapterArray = media["chapters"] as? [[String: Any]] {
                    for (idx, ch) in chapterArray.enumerated() {
                        guard
                            let title = ch["title"] as? String,
                            let start = ch["start"] as? TimeInterval,
                            let end = ch["end"] as? TimeInterval
                        else { continue }

                        chapters.append(
                            .init(id: idx, title: title, start: start, end: end)
                        )
                    }
                }

                if let trackArray = media["tracks"] as? [[String: Any]] {
                    for t in trackArray {
                        guard
                            let index = t["index"] as? Int,
                            let title = t["title"] as? String,
                            let duration = t["duration"] as? TimeInterval,
                            let startOffset = t["startOffset"] as? TimeInterval,
                            let contentUrl = t["contentUrl"] as? String
                        else { continue }

                        tracks.append(
                            .init(
                                id: index,
                                title: title,
                                duration: duration,
                                startOffset: startOffset,
                                contentUrl: contentUrl
                            )
                        )

                        if firstTrackPath == nil {
                            firstTrackPath = contentUrl
                        }
                    }
                }

                await MainActor.run {
                    self.primaryTrackPath = firstTrackPath
                    if !chapters.isEmpty || !tracks.isEmpty {
                        self.audiobookData = AudiobookData(
                            chapters: chapters,
                            tracks: tracks
                        )
                    }
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
}

