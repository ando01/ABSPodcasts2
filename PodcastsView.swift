import SwiftUI

struct PodcastsView: View {
    let client: ABSClient
    let onLogout: () -> Void

    @State private var libraries: [ABSClient.Library] = []
    @State private var selectedLibrary: ABSClient.Library?
    @State private var items: [ABSClient.LibraryItem] = []

    @State private var isLoading = false
    @State private var errorMessage: String?

    // Search text
    @State private var searchText: String = ""

    // Filtered items based on search
    private var filteredItems: [ABSClient.LibraryItem] {
        guard !searchText.isEmpty else { return items }

        let lower = searchText.lowercased()
        return items.filter { item in
            let title = item.displayTitle.lowercased()
            let tags  = item.displayTags.map { $0.lowercased() }.joined(separator: " ")
            return title.contains(lower) || tags.contains(lower)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Library picker (if more than one)
                if !libraries.isEmpty {
                    Menu {
                        ForEach(libraries, id: \.id) { lib in
                            Button(lib.name) {
                                Task { await selectLibrary(lib) }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(selectedLibrary?.name ?? "Select Library")
                                .font(.headline)
                            Image(systemName: "chevron.down")
                                .font(.caption)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    }
                }

                if isLoading && items.isEmpty {
                    ProgressView("Loading podcasts…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .padding()
                    Spacer()
                } else if items.isEmpty {
                    Text("No podcasts found in this library.")
                        .foregroundColor(.secondary)
                        .padding()
                    Spacer()
                } else {
                    ScrollView {
                        if filteredItems.isEmpty && !searchText.isEmpty {
                            Text("No results for “\(searchText)”")
                                .foregroundColor(.secondary)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 140), spacing: 16)],
                                spacing: 16
                            ) {
                                ForEach(filteredItems, id: \.id) { item in
                                    NavigationLink {
                                        EpisodeListView(client: client, libraryItem: item)
                                    } label: {
                                        VStack(alignment: .leading, spacing: 8) {
                                            PodcastCoverView(client: client, item: item)
                                                .frame(height: 140)
                                                .cornerRadius(12)

                                            Text(item.displayTitle)
                                                .font(.caption)
                                                .lineLimit(2)
                                        }
                                    }
                                }
                            }
                            .padding()
                        }
                    }
                }
            }
            .navigationTitle("Library")
            .task {
                await loadLibrariesIfNeeded()
            }
            // 🔍 Search bar
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .automatic),
                prompt: "Search Podcasts"
            )
            // 🔑 Log Out button
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Log Out") {
                        onLogout()
                    }
                }
            }
        }
    }

    // MARK: - Loading

    private func loadLibrariesIfNeeded() async {
        guard libraries.isEmpty else { return }
        isLoading = true
        errorMessage = nil

        do {
            let libs = try await client.fetchLibraries()

            // Prefer podcast libraries if mediaType hints at that
            let podcastLibs = libs.filter { $0.mediaType.lowercased().contains("podcast") }
            let chosenList = podcastLibs.isEmpty ? libs : podcastLibs

            await MainActor.run {
                self.libraries = chosenList
            }

            if let first = chosenList.first {
                await selectLibrary(first)
            } else {
                await MainActor.run { self.isLoading = false }
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    private func selectLibrary(_ library: ABSClient.Library) async {
        await MainActor.run {
            selectedLibrary = library
            isLoading = true
            errorMessage = nil
            items = []
        }

        do {
            let fetched = try await client.fetchLibraryItems(libraryId: library.id)
            await MainActor.run {
                self.items = fetched
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

// MARK: - Helper view for podcast cover art

struct PodcastCoverView: View {
    let client: ABSClient
    let item: ABSClient.LibraryItem

    var body: some View {
        ZStack {
            if let cover = URL.absCoverURL(
                base: client.serverURL,
                itemId: item.id,
                token: client.apiToken,
                width: 400
            ) {
                AsyncImage(url: cover) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure(_):
                        Color.gray.opacity(0.3)
                    default:
                        ProgressView()
                    }
                }
            } else {
                Color.gray.opacity(0.3)
            }
        }
        .clipped()
    }
}

