import SwiftUI

struct EpisodesTabView: View {
    let client: ABSClient
    let onLogout: () -> Void

    struct EpisodeWithPodcast: Identifiable {
        let episode: ABSClient.Episode
        let podcast: ABSClient.LibraryItem

        var id: String { episode.id }
    }

    @State private var episodes: [EpisodeWithPodcast] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    @State private var selectedDateFilter: DateFilter = .all
    @State private var selectedCategory: String? = nil
    @State private var selectedTag: String? = nil

    // All categories/tags from all podcasts
    private var allCategories: [String] {
        let cats = episodes.flatMap { $0.podcast.displayTags }
        return Array(Set(cats)).sorted()
    }

    private var allTags: [String] {
        let tags = episodes.flatMap { $0.podcast.displayTags }
        return Array(Set(tags)).sorted()
    }

    // Apply filters
    private var filteredEpisodes: [EpisodeWithPodcast] {
        episodes.filter { pair in
            let ep = pair.episode
            let item = pair.podcast

            // Date
            if let d = ep.bestDate {
                switch selectedDateFilter {
                case .all:
                    break
                case .last7Days:
                    let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
                    if d < cutoff { return false }
                case .last30Days:
                    let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
                    if d < cutoff { return false }
                }
            }

            // Category (from podcast tags)
            if let selectedCategory {
                if !item.displayTags.contains(selectedCategory) {
                    return false
                }
            }

            // Tag (from podcast tags)
            if let selectedTag {
                if !item.displayTags.contains(selectedTag) {
                    return false
                }
            }

            return true
        }
        // Newest first
        .sorted { ($0.episode.bestDate ?? .distantPast) > ($1.episode.bestDate ?? .distantPast) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                filterBar

                if isLoading && episodes.isEmpty {
                    ProgressView("Loading episodes…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .padding()
                    Spacer()
                } else if filteredEpisodes.isEmpty {
                    Text("No episodes match your filters.")
                        .foregroundColor(.secondary)
                        .padding()
                    Spacer()
                } else {
                    List {
                        ForEach(filteredEpisodes) { pair in
                            NavigationLink {
                                EpisodeDetailView(
                                    episode: pair.episode,
                                    libraryItem: pair.podcast,
                                    client: client
                                )
                            } label: {
                                HStack(spacing: 12) {
                                    PodcastCoverView(client: client, item: pair.podcast)
                                        .frame(width: 60, height: 60)
                                        .cornerRadius(8)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(pair.episode.title)
                                            .font(.headline)
                                            .lineLimit(2)

                                        Text(pair.podcast.displayTitle)
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)

                                        HStack(spacing: 6) {
                                            if let d = pair.episode.bestDate {
                                                Text(d, style: .date)
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                            }
                                            if !pair.podcast.displayTags.isEmpty {
                                                Text(pair.podcast.displayTags.joined(separator: ", "))
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                                    .lineLimit(1)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Episodes")
            .task {
                await loadEpisodesIfNeeded()
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Log Out") {
                        onLogout()
                    }
                }
            }
        }
    }

    // MARK: - Filter bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                // Date
                Menu {
                    Picker("Date", selection: $selectedDateFilter) {
                        ForEach(DateFilter.allCases, id: \.self) { filter in
                            Text(filter.displayName).tag(filter)
                        }
                    }
                } label: {
                    filterChip("Date: \(selectedDateFilter.displayName)")
                }

                // Category
                if !allCategories.isEmpty {
                    Menu {
                        Button("All Categories") { selectedCategory = nil }
                        Divider()
                        ForEach(allCategories, id: \.self) { cat in
                            Button(cat) { selectedCategory = cat }
                        }
                    } label: {
                        filterChip("Category: \(selectedCategory ?? "All")")
                    }
                }

                // Tag
                if !allTags.isEmpty {
                    Menu {
                        Button("All Tags") { selectedTag = nil }
                        Divider()
                        ForEach(allTags, id: \.self) { tag in
                            Button(tag) { selectedTag = tag }
                        }
                    } label: {
                        filterChip("Tag: \(selectedTag ?? "All")")
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color(.systemGroupedBackground))
    }

    private func filterChip(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(.systemGray6))
            .cornerRadius(999)
    }

    // MARK: - Loading

    private func loadEpisodesIfNeeded() async {
        guard episodes.isEmpty else { return }

        isLoading = true
        errorMessage = nil

        do {
            let libs = try await client.fetchLibraries()
            let podcastLibs = libs.filter { $0.mediaType.lowercased().contains("podcast") }
            let libsToUse = podcastLibs.isEmpty ? libs : podcastLibs

            var collected: [EpisodeWithPodcast] = []

            for lib in libsToUse {
                let items = try await client.fetchLibraryItems(libraryId: lib.id)

                for item in items {
                    let eps = try await client.fetchEpisodes(podcastItemId: item.id)
                    let pairs = eps.map { EpisodeWithPodcast(episode: $0, podcast: item) }
                    collected.append(contentsOf: pairs)
                }
            }

            await MainActor.run {
                self.episodes = collected
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

