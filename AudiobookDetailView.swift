import SwiftUI

struct AudiobookDetailView: View {
    let audiobook: ABSClient.LibraryItem
    let serverURL: String
    let apiToken: String

    @EnvironmentObject var playerManager: PlayerManager

    @ObservedObject private var downloadManager = DownloadManager.shared
    private let progressManager = PlaybackProgressManager.shared

    @State private var isDownloading: Bool = false
    @State private var errorMessage: String?
    @State private var isLoadingDetails: Bool = false

    /// First audio file inode for this audiobook (from /api/items/{id}?expanded=1)
    @State private var audioFileIno: String?

    private var audiobookCoverURL: URL? {
        guard let base = URL(string: serverURL) else { return nil }
        return base.appending(path: "/api/items/\(audiobook.id)/cover")
    }

    /// Preferred stream URL for this audiobook:
    /// 1. If we have `ino`, use: /api/items/{id}/file/{ino}?token=...
    /// 2. Fallback to /s/item/{id}?token=... if ino is missing
    private var audiobookStreamURL: URL? {
        guard let base = URL(string: serverURL) else { return nil }

        if let ino = audioFileIno {
            var components = URLComponents(
                url: base.appending(path: "/api/items/\(audiobook.id)/file/\(ino)"),
                resolvingAgainstBaseURL: false
            )
            components?.queryItems = [
                URLQueryItem(name: "token", value: apiToken)
            ]
            let url = components?.url
            print("🎵 [AudiobookDetail] Using /api/items file URL: \(url?.absoluteString ?? "nil")")
            return url
        }

        // Fallback (may 404 on some ABS setups, but better than nothing)
        var components = URLComponents(
            url: base.appending(path: "/s/item/\(audiobook.id)"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "token", value: apiToken)
        ]
        let url = components?.url
        print("🎵 [AudiobookDetail] Fallback /s/item URL: \(url?.absoluteString ?? "nil")")
        return url
    }

    private var hasProgress: Bool {
        progressManager.loadProgress(for: audiobook.id) != nil
    }

    var body: some View {
        List {
            // Header
            Section {
                VStack(spacing: 16) {
                    // Cover
                    if let artworkURL = audiobookCoverURL {
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
                            case .failure:
                                placeholderArtwork
                            @unknown default:
                                placeholderArtwork
                            }
                        }
                    } else {
                        placeholderArtwork
                    }

                    VStack(spacing: 8) {
                        Text(audiobook.displayTitle)
                            .font(.title2)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)

                        if let author = audiobook.media?.metadata?.author {
                            Text(author)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        // tags
                        let tags = audiobook.displayTags
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
                                                    .fill(Color.green.opacity(0.15))
                                            )
                                            .foregroundStyle(.green)
                                    }
                                }
                            }
                        }
                    }

                    if let desc = audiobook.displayDescription, !desc.isEmpty {
                        Text(desc)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(8)
                            .padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }

            // Actions: play + download
            Section {
                if isLoadingDetails {
                    HStack {
                        ProgressView()
                        Text("Loading audiobook details…")
                    }
                } else if let streamURL = audiobookStreamURL {
                    Button {
                        playAudiobook(streamURL: streamURL)
                    } label: {
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

                    Button {
                        Task {
                            await toggleDownload(streamURL: streamURL)
                        }
                    } label: {
                        HStack {
                            if isDownloading {
                                ProgressView()
                                    .scaleEffect(0.9)
                            } else {
                                Image(systemName: downloadManager.isDownloaded(id: audiobook.id) ? "trash" : "arrow.down.circle")
                            }
                            Text(downloadManager.isDownloaded(id: audiobook.id) ? "Remove Download" : "Download for Offline Listening")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.secondary.opacity(0.15))
                        .foregroundStyle(.primary)
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("Unable to build audiobook stream URL.")
                        .foregroundStyle(.red)
                }

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

            // Metadata
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

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.subheadline)
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

    private var placeholderArtwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.gray.opacity(0.2))
                .frame(width: 160, height: 160)
            Image(systemName: "book.closed")
                .font(.system(size: 64))
                .foregroundStyle(.gray)
        }
    }

    // MARK: - Actions

    private func playAudiobook(streamURL: URL) {
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
    }

    private func toggleDownload(streamURL: URL) async {
        if downloadManager.isDownloaded(id: audiobook.id) {
            downloadManager.delete(id: audiobook.id)
            return
        }

        isDownloading = true
        defer { isDownloading = false }

        do {
            try await downloadManager.download(id: audiobook.id, from: streamURL)
            if let cover = audiobookCoverURL {
                await downloadManager.storeArtwork(id: audiobook.id, from: cover)
            }
        } catch {
            print("⚠️ [AudiobookDetail] Download failed for \(audiobook.id): \(error)")
            errorMessage = "Download failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Load ABS details to get ino

    private func loadAudiobookDetails() {
        guard let url = URL(string: serverURL), !apiToken.isEmpty else {
            errorMessage = "Missing server URL or API token."
            return
        }

        isLoadingDetails = true
        errorMessage = nil

        Task {
            do {
                var components = URLComponents(
                    url: url.appending(path: "/api/items/\(audiobook.id)"),
                    resolvingAgainstBaseURL: false
                )
                components?.queryItems = [
                    URLQueryItem(name: "expanded", value: "1")
                ]

                guard let detailURL = components?.url else {
                    throw URLError(.badURL)
                }

                var request = URLRequest(url: detailURL)
                request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")

                let (data, _) = try await URLSession.shared.data(for: request)

                // Parse just enough JSON to get media.audioFiles[0].ino
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let media = json["media"] as? [String: Any],
                   let audioFiles = media["audioFiles"] as? [[String: Any]],
                   let firstFile = audioFiles.first,
                   let inoAny = firstFile["ino"] {

                    // ino might be String or Number, normalize
                    let inoString = String(describing: inoAny)

                    await MainActor.run {
                        self.audioFileIno = inoString
                        print("✅ [AudiobookDetail] Found audio file ino=\(inoString) for id=\(audiobook.id)")
                        self.isLoadingDetails = false
                    }
                } else {
                    await MainActor.run {
                        print("⚠️ [AudiobookDetail] Could not parse audioFiles for id=\(audiobook.id)")
                        self.isLoadingDetails = false
                    }
                }
            } catch {
                await MainActor.run {
                    print("⚠️ [AudiobookDetail] Failed to load details for id=\(audiobook.id): \(error)")
                    self.errorMessage = error.localizedDescription
                    self.isLoadingDetails = false
                }
            }
        }
    }
}

