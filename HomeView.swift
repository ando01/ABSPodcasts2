import SwiftUI

struct HomeView: View {
    let client: ABSClient
    @EnvironmentObject var playerManager: PlayerManager

    @State private var isLoadingContinue = true
    @State private var isLoadingRecent = true

    @State private var continueItems: [ABSClient.LibraryItem] = []
    @State private var recentItems: [ABSClient.LibraryItem] = []

    @State private var selectedLibrary: ABSClient.Library?
    @State private var libraries: [ABSClient.Library] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    // MARK: - Library Picker
                    libraryPickerSection

                    // MARK: - Continue Listening
                    continueListeningSection

                    // MARK: - Recently Added
                    recentAddedSection

                }
                .padding(.horizontal)
            }
            .navigationTitle("Home")
            .task { await loadLibraries() }
        }
    }
}

// MARK: - Sections
extension HomeView {

    // MARK: Library Picker
    private var libraryPickerSection: some View {
        VStack(alignment: .leading) {
            Text("Audiobooks")
                .font(.largeTitle)
                .bold()

            Menu {
                ForEach(libraries) { lib in
                    Button(lib.name) {
                        selectedLibrary = lib
                        Task { await reloadAll(for: lib) }
                    }
                }
            } label: {
                HStack {
                    Text(selectedLibrary?.name ?? "Select Library")
                        .font(.headline)
                    Image(systemName: "chevron.down")
                }
            }
        }
    }

    // MARK: Continue Listening
    private var continueListeningSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Continue Listening")
                .font(.headline)

            if isLoadingContinue {
                ProgressView().padding(.vertical)
            } else if continueItems.isEmpty {
                Text("Nothing to resume yet.")
                    .foregroundColor(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(continueItems) { item in
                            NavigationLink {
                                destinationView(for: item)
                            } label: {
                                recentItemCard(for: item)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Recently Added
    private var recentAddedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recently Added")
                .font(.headline)

            if isLoadingRecent {
                ProgressView().padding(.vertical)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(recentItems) { item in
                            NavigationLink {
                                destinationView(for: item)
                            } label: {
                                recentItemCard(for: item)
                            }
                        }
                    }
                }
            }
        }
    }
}


// MARK: - Navigation Routing
extension HomeView {

    /// Routes audiobooks → AudiobookDetailView
    /// Routes podcasts → EpisodeListView
    @ViewBuilder
    private func destinationView(for item: ABSClient.LibraryItem) -> some View {
        let type = (item.mediaType ?? "").lowercased()

        if type == "book" {
            AudiobookDetailView(item: item, client: client)
        } else {
            EpisodeListView(client: client, libraryItem: item)
        }
    }
}


// MARK: - Cards
extension HomeView {

    private func recentItemCard(for item: ABSClient.LibraryItem) -> some View {
        VStack(spacing: 8) {
            if let u = URL.absCoverURL(
                base: client.serverURL,
                itemId: item.id,
                token: client.apiToken,
                width: 200
            ) {
                AsyncImage(url: u) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFit().frame(width: 120).cornerRadius(10)
                    default:
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 120, height: 120)
                            .cornerRadius(10)
                    }
                }
            }

            Text(item.displayTitle)
                .font(.caption)
                .lineLimit(2)
                .frame(width: 120)
        }
    }
}


// MARK: - Loading Logic
extension HomeView {

    private func loadLibraries() async {
        do {
            libraries = try await client.fetchLibraries()
            if let first = libraries.first {
                selectedLibrary = first
                await reloadAll(for: first)
            }
        } catch {
            print("Failed loading libraries: \(error)")
        }
    }

    private func reloadAll(for library: ABSClient.Library) async {
        await loadRecent(for: library)
        await loadContinue(for: library)
    }

    private func loadRecent(for library: ABSClient.Library) async {
        isLoadingRecent = true
        do {
            var items = try await client.fetchLibraryItems(libraryId: library.id)
            items.sort { ($0.bestDate ?? .distantPast) > ($1.bestDate ?? .distantPast) }
            recentItems = Array(items.prefix(10))
        } catch {
            print("Error: \(error)")
        }
        isLoadingRecent = false
    }

    private func loadContinue(for library: ABSClient.Library) async {
        isLoadingContinue = true
        continueItems = []   // You can populate from playback progress later
        isLoadingContinue = false
    }
}

