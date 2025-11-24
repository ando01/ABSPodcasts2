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
                        HStack(spacing: 12) {
                            AsyncImage(
                                url: URL.absCoverURL(
                                    base: client.serverURL,
                                    itemId: item.id,
                                    token: client.apiToken,
                                    width: 200
                                )
                            ) { phase in
                                switch phase {
                                case .success(let img):
                                    img.resizable().scaledToFill()
                                default:
                                    Color.gray.opacity(0.2)
                                }
                            }
                            .frame(width: 60, height: 60)
                            .cornerRadius(8)
                            .clipped()

                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.displayTitle)
                                    .font(.body)
                                if let desc = item.displayDescription {
                                    Text(desc)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle(library.name)
        .task { await loadItems() }
    }

    private func loadItems() async {
        do {
            let loaded = try await client.fetchLibraryItems(libraryId: library.id)
            await MainActor.run {
                items = loaded
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    // 🔁 Clean routing: books → AudiobookDetailView, others → EpisodeListView
    @ViewBuilder
    private func destination(for item: ABSClient.LibraryItem) -> some View {
        if item.mediaType?.lowercased() == "book" {
            AudiobookDetailView(item: item, client: client)
        } else {
            EpisodeListView(client: client, libraryItem: item)
        }
    }
}

