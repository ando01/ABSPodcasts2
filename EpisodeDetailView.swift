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
                                .cornerRadius(12)
                        case .failure(_):
                            Color.gray.opacity(0.3)
                                .frame(width: 240, height: 240)
                                .cornerRadius(12)
                        default:
                            ProgressView()
                                .frame(width: 240, height: 240)
                        }
                    }
                }
                
                // Title
                Text(episode.title)
                    .font(.title2)
                    .bold()
                
                // 👉 Play button now lives *above* the description
                Button {
                    Task { await play() }
                } label: {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Play Episode")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
                .buttonStyle(.borderedProminent)
                .disabled(loading)
                
                // Loading state under the button
                if loading {
                    ProgressView("Loading…")
                }
                
                // Description
                if let desc = episode.description {
                    Text(desc)
                        .foregroundStyle(.secondary)
                }
                
                // Error (if any)
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                }
                
                Spacer(minLength: 16)
            }
            .padding()
        }
        .navigationTitle("Episode")
        .navigationBarTitleDisplayMode(.inline)
    }
    
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
}

