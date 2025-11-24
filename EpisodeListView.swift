import SwiftUI

struct EpisodeListView: View {
    let client: ABSClient
    let libraryItem: ABSClient.LibraryItem   // Podcasts carry tags/categories
          
    @EnvironmentObject var playerManager: PlayerManager

    @State private var episodes: [ABSClient.Episode] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    // Filters
    @State private var selectedDateFilter: DateFilter = .all
    @State private var selectedTag: String? = nil
    @State private var selectedCategory: String? = nil

    // Categories/tags come from the *podcast’s* metadata
    private var allTags: [String] {
        libraryItem.displayTags.sorted()
    }

    // For podcasts, categories == tags (ABS doesn’t distinguish)
    private var allCategories: [String] {
        libraryItem.displayTags.sorted()
    }

    // Apply filters to episodes
    private var filteredEpisodes: [ABSClient.Episode] {
        episodes.filter { ep in
            // Date filter
            if let d = ep.bestDate {
                switch selectedDateFilter {
                case .all:
                    break
                case .last7Days:
                    let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
                    if d < weekAgo { return false }
                case .last30Days:
                    let monthAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
                    if d < monthAgo { return false }
                }
            }

            // Category filter (mapped from libraryItem.displayTags)
            if let selectedCategory {
                if !libraryItem.displayTags.contains(selectedCategory) {
                    return false
                }
            }

            // Tag filter (mapped from libraryItem.displayTags)
            if let selectedTag {
                if !libraryItem.displayTags.contains(selectedTag) {
                    return false
                }
            }

            return true
        }
    }

    var body: some View {
        VStack(spacing: 0) {

            filterBar

            if isLoading && episodes.isEmpty {
                ProgressView("Loading episodes…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundColor(.red)
                    }

                    ForEach(filteredEpisodes) { ep in
                        NavigationLink {
                            EpisodeDetailView(
                                episode: ep,
                                libraryItem: libraryItem,
                                client: client
                            )
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(ep.title)
                                    .font(.headline)

                                if let desc = ep.description {
                                    Text(desc)
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                }

                                if let best = ep.bestDate {
                                    Text(best, style: .date)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(libraryItem.displayTitle)
        .task { await loadEpisodes() }
    }

    // MARK: - Filters bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {

                // Date filter
                Menu {
                    Picker("Date", selection: $selectedDateFilter) {
                        ForEach(DateFilter.allCases, id: \.self) { filter in
                            Text(filter.displayName).tag(filter)
                        }
                    }
                } label: {
                    filterChip("Date: \(selectedDateFilter.displayName)")
                }

                // Categories (mapped from item tags)
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

                // Tags
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

    // MARK: - Load

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

// MARK: - Date Filters

enum DateFilter: CaseIterable {
    case all, last7Days, last30Days
    
    var displayName: String {
        switch self {
        case .all: return "All"
        case .last7Days: return "Last 7 Days"
        case .last30Days: return "Last 30 Days"
        }
    }
}

