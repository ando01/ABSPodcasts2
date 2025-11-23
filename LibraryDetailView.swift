import SwiftUI

struct LibraryDetailView: View {
    let client: ABSClient
    let library: ABSClient.Library

    @State private var items: [ABSClient.LibraryItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading…")
            } else {
                List(items) { item in
                    NavigationLink {
                        destination(for: item)
                    } label: {
                        HStack {
                            AsyncImage(url: URL.absCoverURL(
                                base: client.serverURL,
                                itemId: item.id,
                                token: client.apiToken,
                                width: 100
                            )) { phase in
                                switch phase {
                                case .success(let img): img.resizable().scaledToFit()
                                default: Color.gray.opacity(0.2)
                                }
                            }
                            .frame(width: 60, height: 60)
                            .cornerRadius(8)

                            Text(item.displayTitle)
                        }
                    }
                }
            }
        }
        .navigationTitle(library.name)
        .task { await loadItems() }
    }

    private func loadItems() async {
        do {
            items = try await client.fetchLibraryItems(libraryId: library.id)
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    // Route audiobooks vs podcasts
    @ViewBuilder
    private func destination(for item: ABSClient.LibraryItem) -> some View {
        if item.mediaType?.lowercased() == "book" {
            AudiobookDetailView(item: item, client: client)
        } else {
            EpisodeListView(client: client, libraryItem: item)
        }
    }
}

