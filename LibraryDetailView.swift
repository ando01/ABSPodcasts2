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
    
    // Animation
    @Namespace private var animation
    
    enum SortOption: String, CaseIterable, Identifiable {
        case titleAZ = "Title (A-Z)"
        case titleZA = "Title (Z-A)"
        case newestFirst = "Newest First"
        case oldestFirst = "Oldest First"
        
        var id: String { rawValue }
    }
    
    private var isPodcastLibrary: Bool {
        library.mediaType.lowercased() == "podcast"
    }
    
    private var allTags: [String] {
        let tagSet = items.flatMap { $0.displayTags }
        return Array(Set(tagSet)).sorted()
    }
    
    private var filteredItems: [ABSClient.LibraryItem] {
        var result = items
        
        if !searchText.isEmpty {
            result = result.filter { item in
                item.displayTitle.localizedCaseInsensitiveContains(searchText) ||
                (item.displayDescription?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                (item.media?.metadata?.author?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
        
        if let tag = selectedTag {
            result = result.filter { $0.displayTags.contains(tag) }
        }
        
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
    
    private func coverArtURL(for item: ABSClient.LibraryItem) -> URL? {
        guard let base = URL(string: serverURL) else { return nil }
        return base.appending(path: "/api/items/\(item.id)/cover")
    }

    var body: some View {
        List {
            // Library header with animation
            Section {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(isPodcastLibrary ? Color.blue.opacity(0.15) : Color.green.opacity(0.15))
                            .frame(width: 50, height: 50)
                        
                        Image(systemName: isPodcastLibrary ? "mic.fill" : "book.fill")
                            .font(.title2)
                            .foregroundStyle(isPodcastLibrary ? .blue : .green)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(library.name)
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text("\(filteredItems.count) \(isPodcastLibrary ? "Podcasts" : "Audiobooks")")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            
            // Active filters with slide animation
            if selectedTag != nil || sortOption != .newestFirst {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            if let tag = selectedTag {
                                FilterChip(text: "Tag: \(tag)") {
                                    withAnimation(.spring(response: 0.3)) {
                                        selectedTag = nil
                                    }
                                }
                                .transition(.scale.combined(with: .opacity))
                            }
                            
                            if sortOption != .newestFirst {
                                FilterChip(text: sortOption.rawValue, isSort: true) {
                                    withAnimation(.spring(response: 0.3)) {
                                        sortOption = .newestFirst
                                    }
                                }
                                .transition(.scale.combined(with: .opacity))
                            }
                            
                            if selectedTag != nil || sortOption != .newestFirst {
                                Button {
                                    withAnimation(.spring(response: 0.3)) {
                                        selectedTag = nil
                                        sortOption = .newestFirst
                                    }
                                } label: {
                                    Text("Clear All")
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(
                                            Capsule()
                                                .fill(Color.red.opacity(0.1))
                                        )
                                }
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                }
            }

            // Error display with shake animation
            if let errorMessage {
                Section(header: Text("Error")) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.subheadline)
                    }
                }
                .transition(.opacity.combined(with: .scale))
            }

            // Loading state with skeleton
            if isLoading {
                Section {
                    ForEach(0..<5, id: \.self) { _ in
                        SkeletonItemRow()
                    }
                }
            }
            // Items list with staggered animation
            else if !items.isEmpty {
                Section {
                    if filteredItems.isEmpty {
                        LibraryEmptyStateView(
                            icon: "magnifyingglass",
                            message: "No items match your filters"
                        )
                    } else {
                        ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, item in
                            NavigationLink(destination: destinationView(for: item)) {
                                ItemRow(
                                    item: item,
                                    artworkURL: coverArtURL(for: item),
                                    isPodcast: isPodcastLibrary
                                )
                            }
                            .buttonStyle(.plain)
                            .contentShape(Rectangle())
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .offset(y: 20)),
                                removal: .opacity
                            ))
                            .animation(.spring(response: 0.4, dampingFraction: 0.8).delay(Double(index) * 0.05), value: filteredItems.count)
                        }
                    }
                }
            }
            // Empty state
            else {
                Section {
                    LibraryEmptyStateView(
                        icon: isPodcastLibrary ? "mic.slash" : "book.closed",
                        message: "No items found in this library"
                    )
                }
            }
        }
        .navigationTitle(library.name)
        .searchable(text: $searchText, prompt: isPodcastLibrary ? "Search podcasts" : "Search audiobooks")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    withAnimation {
                        showingFilterSheet = true
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.1))
                            .frame(width: 36, height: 36)
                        
                        Image(systemName: "line.3.horizontal.decrease.circle.fill")
                            .foregroundStyle(.blue)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showingFilterSheet) {
            FilterSheet(
                allTags: allTags,
                selectedTag: $selectedTag,
                sortOption: $sortOption
            )
            .presentationDetents([.medium, .large])
        }
        .onAppear {
            loadItems()
        }
        .refreshable {
            await refreshItems()
        }
    }
    
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
                    withAnimation(.spring(response: 0.4)) {
                        self.items = fetched
                        self.isLoading = false
                    }
                }
            } catch {
                await MainActor.run {
                    withAnimation {
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
    
    private func refreshItems() async {
        guard let url = URL(string: serverURL), !apiToken.isEmpty else { return }
        let client = ABSClient(serverURL: url, apiToken: apiToken)
        
        do {
            let fetched = try await client.fetchLibraryItems(libraryId: library.id)
            await MainActor.run {
                withAnimation(.spring(response: 0.4)) {
                    self.items = fetched
                }
            }
        } catch {
            // Silently fail on refresh
        }
    }
}

// MARK: - Item Row Component

struct ItemRow: View {
    let item: ABSClient.LibraryItem
    let artworkURL: URL?
    let isPodcast: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            // Cover Art with loading animation
            AsyncImage(url: artworkURL) { phase in
                switch phase {
                case .empty:
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 60, height: 60)
                        
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                        .transition(.scale.combined(with: .opacity))
                case .failure:
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 60, height: 60)
                        Image(systemName: isPodcast ? "music.note" : "book.closed")
                            .font(.system(size: 24))
                            .foregroundStyle(.gray)
                    }
                @unknown default:
                    EmptyView()
                }
            }
            
            // Item Info
            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayTitle)
                    .font(.body)
                    .fontWeight(.medium)
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
                            ForEach(tags.prefix(3), id: \.self) { tag in
                                Text(tag)
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(isPodcast ? Color.blue.opacity(0.15) : Color.green.opacity(0.15))
                                    )
                                    .foregroundStyle(isPodcast ? .blue : .green)
                            }
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Skeleton Loading View

struct SkeletonItemRow: View {
    @State private var isAnimating = false
    
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.2))
                .frame(width: 60, height: 60)
            
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 16)
                    .frame(maxWidth: .infinity)
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 12)
                    .frame(width: 120)
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 12)
                    .frame(maxWidth: 200)
            }
        }
        .padding(.vertical, 4)
        .opacity(isAnimating ? 0.5 : 1.0)
        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isAnimating)
        .onAppear {
            isAnimating = true
        }
    }
}

// MARK: - Empty State View

private struct LibraryEmptyStateView: View {
    let icon: String
    let message: String
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(.gray.opacity(0.5))
            
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
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
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
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
                Section(header: Text("Sort By")) {
                    ForEach(LibraryDetailView.SortOption.allCases) { option in
                        Button {
                            withAnimation(.spring(response: 0.3)) {
                                sortOption = option
                            }
                        } label: {
                            HStack {
                                Text(option.rawValue)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if sortOption == option {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                        .transition(.scale.combined(with: .opacity))
                                }
                            }
                        }
                    }
                }
                
                Section(header: Text("Filter by Tag/Category")) {
                    if allTags.isEmpty {
                        Text("No tags available")
                            .foregroundStyle(.secondary)
                    } else {
                        Button {
                            withAnimation(.spring(response: 0.3)) {
                                selectedTag = nil
                            }
                        } label: {
                            HStack {
                                Text("All Items")
                                    .foregroundStyle(.primary)
                                Spacer()
                                if selectedTag == nil {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                        
                        ForEach(allTags, id: \.self) { tag in
                            Button {
                                withAnimation(.spring(response: 0.3)) {
                                    selectedTag = tag
                                }
                            } label: {
                                HStack {
                                    Text(tag)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if selectedTag == tag {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.blue)
                                            .transition(.scale.combined(with: .opacity))
                                    }
                                }
                            }
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
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

#Preview {
    LibraryDetailView(
        library: ABSClient.Library(id: "demo", name: "Podcasts", mediaType: "podcast", icon: nil),
        serverURL: "https://example.com",
        apiToken: "demo"
    )
}
