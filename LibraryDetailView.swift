import SwiftUI

struct LibraryDetailView: View {
    let library: ABSClient.Library
    let serverURL: String
    let apiToken: String

    @State private var items: [ABSClient.LibraryItem] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil
    
    // Filtering & Sorting
    @State private var searchText: String = ""
    @State private var selectedTag: String? = nil
    @State private var sortOption: SortOption = .newestFirst
    @State private var showingFilterSheet: Bool = false
    
    enum SortOption: String, CaseIterable, Identifiable {
        case titleAZ = "Title (A-Z)"
        case titleZA = "Title (Z-A)"
        case newestFirst = "Newest First"
        case oldestFirst = "Oldest First"
        
        var id: String { rawValue }
    }
    
    // Check if this is a podcast library
    private var isPodcastLibrary: Bool {
        library.mediaType.lowercased() == "podcast"
    }
    
    // Computed: all unique tags from items
    private var allTags: [String] {
        let tagSet = items.flatMap { $0.displayTags }
        return Array(Set(tagSet)).sorted()
    }
    
    // Computed: filtered and sorted items
    private var filteredItems: [ABSClient.LibraryItem] {
        var result = items
        
        // Filter by search text
        if !searchText.isEmpty {
            result = result.filter { item in
                item.displayTitle.localizedCaseInsensitiveContains(searchText) ||
                (item.displayDescription?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                (item.media?.metadata?.author?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
        
        // Filter by selected tag
        if let tag = selectedTag {
            result = result.filter { $0.displayTags.contains(tag) }
        }
        
        // Sort
        switch sortOption {
        case .titleAZ:
            result.sort { $0.displayTitle.localizedCompare($1.displayTitle) == .orderedAscending }
        case .titleZA:
            result.sort { $0.displayTitle.localizedCompare($1.displayTitle) == .orderedDescending }
        case .newestFirst:
            result.sort { ($0.bestDate ?? .distantPast) > ($1.bestDate ?? .distantPast) }
        case .oldestFirst:
            result.sort { ($0.bestDate ?? .distantPast) < ($1.bestDate ?? .distantPast) }
        }
        
        return result
    }
    
    // Helper to build cover art URL
    private func coverArtURL(for item: ABSClient.LibraryItem) -> URL? {
        guard let base = URL(string: serverURL) else { return nil }
        return base.appending(path: "/api/items/\(item.id)/cover")
    }

    var body: some View {
        List {
            // Library info section
            Section {
                HStack {
                    Image(systemName: isPodcastLibrary ? "mic.fill" : "book.fill")
                        .foregroundStyle(isPodcastLibrary ? .blue : .green)
                    VStack(alignment: .leading) {
                        Text(library.name)
                            .font(.title2)
                        Text(isPodcastLibrary ? "Podcasts" : "Audiobooks")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            // Active filters display
            if selectedTag != nil || sortOption != .newestFirst {
                Section {
                    HStack {
                        if let tag = selectedTag {
                            FilterChip(text: "Tag: \(tag)") {
                                selectedTag = nil
                            }
                        }
                        
                        if sortOption != .newestFirst {
                            FilterChip(text: sortOption.rawValue, isSort: true) {
                                sortOption = .newestFirst
                            }
                        }
                        
                        Spacer()
                        
                        if selectedTag != nil || sortOption != .newestFirst {
                            Button("Clear All") {
                                selectedTag = nil
                                sortOption = .newestFirst
                            }
                            .font(.caption)
                            .foregroundStyle(.blue)
                        }
                    }
                }
            }

            // Error display
            if let errorMessage {
                Section(header: Text("Error")) {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.subheadline)
                }
            }

            // Loading state
            if isLoading {
                Section {
                    HStack {
                        ProgressView()
                        Text("Loading items…")
                    }
                }
            }
            // Items list
            else if !items.isEmpty {
                Section(header: HStack {
                    Text("\(isPodcastLibrary ? "Podcasts" : "Audiobooks") (\(filteredItems.count))")
                    Spacer()
                }) {
                    if filteredItems.isEmpty {
                        Text("No items match your filters")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(filteredItems) { item in
                            NavigationLink(
                                destination: destinationView(for: item)
                            ) {
                                HStack(spacing: 12) {
                                    // Cover Art
                                    if let artworkURL = coverArtURL(for: item) {
                                        AsyncImage(url: artworkURL) { phase in
                                            switch phase {
                                            case .empty:
                                                ProgressView()
                                                    .frame(width: 60, height: 60)
                                            case .success(let image):
                                                image
                                                    .resizable()
                                                    .scaledToFill()
                                                    .frame(width: 60, height: 60)
                                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                            case .failure:
                                                placeholderArtwork(for: item)
                                            @unknown default:
                                                placeholderArtwork(for: item)
                                            }
                                        }
                                    } else {
                                        placeholderArtwork(for: item)
                                    }
                                    
                                    // Item Info
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.displayTitle)
                                            .font(.body)
                                            .lineLimit(2)
                                        
                                        if let author = item.media?.metadata?.author {
                                            Text(author)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }

                                        if let desc = item.displayDescription, !desc.isEmpty {
                                            Text(desc)
                                                .font(.caption)
                                                .lineLimit(2)
                                                .foregroundStyle(.secondary)
                                        }

                                        let tags = item.displayTags
                                        if !tags.isEmpty {
                                            ScrollView(.horizontal, showsIndicators: false) {
                                                HStack(spacing: 4) {
                                                    ForEach(tags, id: \.self) { tag in
                                                        Text(tag)
                                                            .font(.caption2)
                                                            .padding(.horizontal, 6)
                                                            .padding(.vertical, 2)
                                                            .background(
                                                                RoundedRectangle(cornerRadius: 4)
                                                                    .fill(isPodcastLibrary ? Color.blue.opacity(0.15) : Color.green.opacity(0.15))
                                                            )
                                                            .foregroundStyle(isPodcastLibrary ? .blue : .green)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
            }
            // Empty state
            else {
                Section {
                    Text("No items found in this library.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(library.name)
        .searchable(text: $searchText, prompt: isPodcastLibrary ? "Search podcasts" : "Search audiobooks")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingFilterSheet = true
                } label: {
                    Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
                }
            }
        }
        .sheet(isPresented: $showingFilterSheet) {
            FilterSheet(
                allTags: allTags,
                selectedTag: $selectedTag,
                sortOption: $sortOption
            )
        }
        .onAppear {
            loadItems()
        }
    }
    
    // MARK: - Destination View Router
    
    @ViewBuilder
    private func destinationView(for item: ABSClient.LibraryItem) -> some View {
        if isPodcastLibrary {
            PodcastDetailView(
                podcast: item,
                serverURL: serverURL,
                apiToken: apiToken
            )
        } else {
            AudiobookDetailView(
                audiobook: item,
                serverURL: serverURL,
                apiToken: apiToken
            )
        }
    }
    
    private func placeholderArtwork(for item: ABSClient.LibraryItem) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.2))
                .frame(width: 60, height: 60)
            Image(systemName: isPodcastLibrary ? "music.note" : "book.closed")
                .font(.system(size: 24))
                .foregroundStyle(.gray)
        }
    }

    private func loadItems() {
        guard let url = URL(string: serverURL), !apiToken.isEmpty else {
            errorMessage = "Missing server URL or API token."
            return
        }

        let client = ABSClient(serverURL: url, apiToken: apiToken)
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let fetched = try await client.fetchLibraryItems(libraryId: library.id)
                await MainActor.run {
                    self.items = fetched
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    if let absErr = error as? ABSClient.ABSError {
                        errorMessage = absErr.localizedDescription
                    } else {
                        errorMessage = error.localizedDescription
                    }
                    isLoading = false
                }
            }
        }
    }
}

// MARK: - Filter Chip Component

struct FilterChip: View {
    let text: String
    var isSort: Bool = false
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: isSort ? "arrow.up.arrow.down" : "tag.fill")
                .font(.caption2)
            Text(text)
                .font(.caption)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.blue.opacity(0.15))
        )
        .foregroundStyle(.blue)
    }
}

// MARK: - Filter Sheet

struct FilterSheet: View {
    let allTags: [String]
    @Binding var selectedTag: String?
    @Binding var sortOption: LibraryDetailView.SortOption
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                // Sort section
                Section(header: Text("Sort By")) {
                    Picker("Sort", selection: $sortOption) {
                        ForEach(LibraryDetailView.SortOption.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                
                // Filter by tag section
                Section(header: Text("Filter by Tag/Category")) {
                    if allTags.isEmpty {
                        Text("No tags available")
                            .foregroundStyle(.secondary)
                    } else {
                        Button {
                            selectedTag = nil
                        } label: {
                            HStack {
                                Text("All Items")
                                Spacer()
                                if selectedTag == nil {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                        
                        ForEach(allTags, id: \.self) { tag in
                            Button {
                                selectedTag = tag
                            } label: {
                                HStack {
                                    Text(tag)
                                    Spacer()
                                    if selectedTag == tag {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.blue)
                                    }
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }
            }
            .navigationTitle("Filters & Sorting")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    LibraryDetailView(
        library: ABSClient.Library(id: "demo", name: "Podcasts", mediaType: "podcast", icon: nil),
        serverURL: "https://example.com",
        apiToken: "demo"
    )
}
