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
    @State private var sortOption: SortOption = .titleAZ
    @State private var showingFilterSheet: Bool = false
    
    enum SortOption: String, CaseIterable, Identifiable {
        case titleAZ = "Title (A-Z)"
        case titleZA = "Title (Z-A)"
        case newestFirst = "Newest First"
        case oldestFirst = "Oldest First"
        
        var id: String { rawValue }
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
                (item.displayDescription?.localizedCaseInsensitiveContains(searchText) ?? false)
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

    var body: some View {
        List {
            // Library info section
            Section {
                Text(library.name)
                    .font(.title2)
                Text("Media type: \(library.mediaType)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            // Active filters display
            if selectedTag != nil || sortOption != .titleAZ {
                Section {
                    HStack {
                        if let tag = selectedTag {
                            FilterChip(text: "Tag: \(tag)") {
                                selectedTag = nil
                            }
                        }
                        
                        if sortOption != .titleAZ {
                            FilterChip(text: sortOption.rawValue, isSort: true) {
                                sortOption = .titleAZ
                            }
                        }
                        
                        Spacer()
                        
                        if selectedTag != nil || sortOption != .titleAZ {
                            Button("Clear All") {
                                selectedTag = nil
                                sortOption = .titleAZ
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
                    Text("Podcasts (\(filteredItems.count))")
                    Spacer()
                }) {
                    if filteredItems.isEmpty {
                        Text("No podcasts match your filters")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(filteredItems) { item in
                            NavigationLink(
                                destination: PodcastDetailView(
                                    podcast: item,
                                    serverURL: serverURL,
                                    apiToken: apiToken
                                )
                            ) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.displayTitle)
                                        .font(.body)

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
                                                                .fill(Color.blue.opacity(0.15))
                                                        )
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
        .searchable(text: $searchText, prompt: "Search podcasts")
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
                                Text("All Podcasts")
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
