import SwiftUI

struct EpisodeDetailView: View {
    let episode: ABSClient.Episode
    let libraryItem: ABSClient.LibraryItem
    let client: ABSClient
    
    @EnvironmentObject var playerManager: PlayerManager
    @State private var loading = false
    @State private var errorMessage: String?
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // Artwork
                if let cover = URL.absCoverURL(
                    base: client.serverURL,
                    itemId: libraryItem.id,
                    token: client.apiToken,
                    width: 400
                ) {
                    AsyncImage(url: cover) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: 240)
                        case .failure(_):
                            Color.gray.opacity(0.3)
                                .frame(width: 240, height: 240)
                        default:
                            ProgressView()
                        }
                    }
                }

                // Title
                Text(episode.title)
                    .font(.title2)
                    .bold()

                // Play button ABOVE description
                Button {
                    Task { await play() }
                } label: {
                    Label("Play Episode", systemImage: "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(20)
                }
                .buttonStyle(.plain)

                if loading {
                    ProgressView("Loading…")
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                }

                // Cleaned-up description (no HTML tags)
                if let desc = episode.description,
                   !desc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(plainText(fromHTML: desc))
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding()
        }
        .navigationTitle("Episode")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    // MARK: - Playback
    
    private func play() async {
        loading = true
        errorMessage = nil
        
        do {
            guard let urlString = episode.enclosureURLString,
                  let url = URL(string: urlString)
            else {
                throw URLError(.badURL)
            }
            
            playerManager.start(
                libraryItem: libraryItem,
                episode: episode,
                audioURL: url,
                artworkURL: URL.absCoverURL(
                    base: client.serverURL,
                    itemId: libraryItem.id,
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

    // MARK: - HTML → plain text

    private func plainText(fromHTML html: String) -> String {
        guard let data = html.data(using: .utf8) else { return html }
        do {
            let attributed = try NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ],
                documentAttributes: nil
            )
            return attributed.string
        } catch {
            // If parsing fails, just show the original
            return html
        }
    }
}

