import SwiftUI

struct EpisodeListView: View {
    let client: ABSClient
    let libraryItem: ABSClient.LibraryItem
    
    @EnvironmentObject var playerManager: PlayerManager
    
    @State private var episodes: [ABSClient.Episode] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    
    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
            }
            
            ForEach(episodes) { ep in
                NavigationLink {
                    EpisodeDetailView(
                        episode: ep,
                        libraryItem: libraryItem,
                        client: client
                    )
                } label: {
                    VStack(alignment: .leading) {
                        Text(ep.title)
                            .font(.headline)
                        if let desc = ep.description {
                            Text(desc)
                                .lineLimit(2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(libraryItem.displayTitle)
        .task { await loadEpisodes() }
    }
    
    private func loadEpisodes() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let eps = try await client.fetchEpisodes(podcastItemId: libraryItem.id)
            await MainActor.run {
                episodes = eps.sorted { ($0.bestDate ?? .distantPast) > ($1.bestDate ?? .distantPast) }
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
}
