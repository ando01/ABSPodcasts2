import SwiftUI

struct AudiobookDetailView: View {
    let item: ABSClient.LibraryItem
    let client: ABSClient

    @EnvironmentObject var playerManager: PlayerManager

    @State private var loading = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // Cover
                if let coverURL = URL.absCoverURL(
                    base: client.serverURL,
                    itemId: item.id,
                    token: client.apiToken,
                    width: 400
                ) {
                    AsyncImage(url: coverURL) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable()
                                .scaledToFit()
                                .frame(maxWidth: 240)
                                .cornerRadius(12)
                                .shadow(radius: 4)

                        case .failure(_):
                            Color.gray.opacity(0.2)
                                .frame(width: 240, height: 240)
                                .cornerRadius(12)

                        default:
                            ProgressView()
                                .frame(width: 240, height: 240)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                // Title
                Text(item.displayTitle)
                    .font(.title2)
                    .bold()

                // Description
                if let desc = item.displayDescription, !desc.isEmpty {
                    Text(desc)
                        .foregroundStyle(.secondary)
                }

                Divider().padding(.vertical, 8)

                // Error output
                if let err = errorMessage {
                    Text(err)
                        .foregroundColor(.red)
                }

                // Play button
                Button(action: loadAndPlay) {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Play Audiobook")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .disabled(loading)

                if loading {
                    ProgressView("Loading audio…")
                        .padding(.top, 4)
                }

                Spacer()
            }
            .padding()
        }
        .navigationTitle(item.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Load & Play Audiobook

    private func loadAndPlay() {
        loading = true
        errorMessage = nil

        Task {
            do {
                // Request the stream URL
                let playURL = try await client.streamURLForLibraryItem(id: item.id)

                // Build a fake Episode wrapper (Audiobookshelf doesn't use podcast episodes)
                let episode = ABSClient.Episode(
                    id: item.id,
                    title: item.displayTitle,
                    description: item.displayDescription,
                    pubDate: nil,
                    publishedAt: nil,
                    enclosure: .init(
                        url: playURL.absoluteString,
                        type: "audio/mpeg",
                        length: nil
                    )
                )

                // Start playback
                playerManager.start(
                    libraryItem: item,
                    episode: episode,
                    audioURL: playURL,
                    artworkURL: URL.absCoverURL(
                        base: client.serverURL,
                        itemId: item.id,
                        token: client.apiToken
                    ),
                    autoPlay: true,
                    presentNowPlaying: true,
                    resumeFromLastPosition: true
                )

            } catch {
                errorMessage = error.localizedDescription
            }

            loading = false
        }
    }
}

