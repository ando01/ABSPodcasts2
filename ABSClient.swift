import Foundation

struct ABSClient {
    let serverURL: URL
    let apiToken: String

    // MARK: - Errors

    enum ABSError: Error, LocalizedError {
        case invalidResponse
        case httpStatus(Int)
        case decodingError(Error)
        case other(Error)

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "Invalid response from server."
            case .httpStatus(let code):
                return "Server error: HTTP \(code)"
            case .decodingError(let err):
                return "Failed to read server data: \(err.localizedDescription)"
            case .other(let err):
                return err.localizedDescription
            }
        }
    }

    // MARK: - Library + Item models

    struct LibrariesResponse: Decodable {
        let libraries: [Library]
    }

    struct Library: Identifiable, Decodable, Hashable {
        let id: String
        let name: String
        let mediaType: String
        let icon: String?
    }

    /// Wrapper for various possible response shapes for item lists
    private struct LibraryItemsWrapper: Decodable {
        let libraryItems: [LibraryItem]?
        let results: [LibraryItem]?
        let items: [LibraryItem]?

        var allItems: [LibraryItem] {
            libraryItems ?? results ?? items ?? []
        }
    }

    /// Audiobookshelf Library Item (used for podcasts/books)
    struct LibraryItem: Identifiable, Decodable, Hashable {
        let id: String
        let libraryId: String?
        let mediaType: String?
        let media: Media?
        let tags: [String]?

        struct Media: Decodable, Hashable {
            let metadata: Metadata?
            let coverPath: String?
            let tags: [String]?
        }

        struct Metadata: Decodable, Hashable {
            let title: String?
            let subtitle: String?
            let description: String?
            let genres: [String]?
            let author: String?
            let releaseDate: String?
            let publishedAt: String?
            let addedAt: String?
        }

        // Convenience properties for the UI
        var displayTitle: String {
            media?.metadata?.title ?? "Untitled"
        }

        var displayDescription: String? {
            media?.metadata?.description
        }

        var displayTags: [String] {
            if let t = tags, !t.isEmpty {
                return t
            }
            if let t = media?.tags, !t.isEmpty {
                return t
            }
            if let g = media?.metadata?.genres, !g.isEmpty {
                return g
            }
            return []
        }

        /// Best guess at a date for sorting (releaseDate > publishedAt > addedAt)
        var bestDate: Date? {
            guard let meta = media?.metadata else { return nil }
            let candidate = meta.releaseDate ?? meta.publishedAt ?? meta.addedAt
            guard let candidate else { return nil }

            // Try ISO8601 first
            let iso = ISO8601DateFormatter()
            if let d = iso.date(from: candidate) {
                return d
            }

            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
            return f.date(from: candidate)
        }
    }

    // MARK: - Episode models (for media.episodes / podcasts)

    struct Episode: Identifiable, Decodable {
        let id: String
        let title: String
        let description: String?
        let pubDate: String?
        let publishedAt: Double?
        let enclosure: Enclosure?

        struct Enclosure: Decodable {
            let url: String?
            let type: String?
            let length: String?
        }

        /// Convenient access to the audio URL string
        var enclosureURLString: String? {
            enclosure?.url
        }

        /// Choose best date: publishedAt (ms) > pubDate string
        var bestDate: Date? {
            if let ms = publishedAt {
                return Date(timeIntervalSince1970: ms / 1000.0)
            }
            if let s = pubDate {
                let f = DateFormatter()
                f.locale = Locale(identifier: "en_US_POSIX")
                f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
                return f.date(from: s)
            }
            return nil
        }
    }

    /// Shape of /api/items/<id>?expand=children for podcasts
    private struct ItemWithEpisodes: Decodable {
        let media: MediaWithEpisodes?

        struct MediaWithEpisodes: Decodable {
            let episodes: [Episode]?
        }
    }

    // MARK: - API: libraries & items

    /// Fetch all libraries the user can access.
    func fetchLibraries() async throws -> [Library] {
        let url = serverURL.appending(path: "/api/libraries")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ABSError.other(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw ABSError.invalidResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            throw ABSError.httpStatus(http.statusCode)
        }

        do {
            let decoder = JSONDecoder()
            let decoded = try decoder.decode(LibrariesResponse.self, from: data)
            return decoded.libraries
        } catch {
            throw ABSError.decodingError(error)
        }
    }

    /// Fetch top-level items (podcasts, books, etc.) in a given library.
    func fetchLibraryItems(libraryId: String) async throws -> [LibraryItem] {
        let url = serverURL.appending(path: "/api/libraries/\(libraryId)/items")
        return try await fetchItems(from: url)
    }

    // Shared item-fetching logic for LibraryItem
    private func fetchItems(from url: URL) async throws -> [LibraryItem] {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ABSError.other(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw ABSError.invalidResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            throw ABSError.httpStatus(http.statusCode)
        }

        do {
            let decoder = JSONDecoder()

            if let wrapper = try? decoder.decode(LibraryItemsWrapper.self, from: data) {
                let items = wrapper.allItems
                if !items.isEmpty {
                    return items
                }
            }

            let array = try decoder.decode([LibraryItem].self, from: data)
            return array
        } catch {
            if let jsonString = String(data: data, encoding: .utf8) {
                print("DEBUG: Failed to decode items. Raw JSON:\n\(jsonString)")
            }
            throw ABSError.decodingError(error)
        }
    }

    // MARK: - API: episodes for a podcast item

    /// Fetch episodes for a given podcast library item.
    /// Uses /api/items/<podcastId>?expand=children and reads media.episodes.
    func fetchEpisodes(podcastItemId: String) async throws -> [Episode] {
        var components = URLComponents(
            url: serverURL.appending(path: "/api/items/\(podcastItemId)"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "expand", value: "children")
        ]

        guard let url = components.url else {
            throw ABSError.other(URLError(.badURL))
        }

        print("DEBUG: fetching episodes from \(url.absoluteString)")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ABSError.other(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw ABSError.invalidResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            throw ABSError.httpStatus(http.statusCode)
        }

        do {
            let decoder = JSONDecoder()
            let decoded = try decoder.decode(ItemWithEpisodes.self, from: data)
            let episodes = decoded.media?.episodes ?? []
            return episodes
        } catch {
            if let jsonString = String(data: data, encoding: .utf8) {
                print("DEBUG: Failed to decode episodes. Raw JSON:\n\(jsonString)")
            }
            throw ABSError.decodingError(error)
        }
    }

    // MARK: - API: stream URL for a library item (audiobook, etc.)

    /// Gets a playable direct stream URL for a library item (e.g. audiobook)
    /// by calling /api/items/<id>/play and reading the "url" field.
    func streamURLForLibraryItem(id libraryItemId: String) async throws -> URL {
        let endpoint = serverURL.appending(path: "/api/items/\(libraryItemId)/play")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET" // change to POST if your server expects it
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode)
        else {
            throw ABSError.httpStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
        }

        struct PlayResponse: Decodable {
            let url: String
        }

        let decoded = try JSONDecoder().decode(PlayResponse.self, from: data)

        guard let url = URL(string: decoded.url) else {
            throw ABSError.invalidResponse
        }

        return url
    }
}

// MARK: - URL helper for cover artwork

extension URL {
    /// Build the Audiobookshelf cover URL:
    ///   <base>/api/items/<itemId>/cover?width=<width>&token=<token>
    static func absCoverURL(
        base: URL?,
        itemId: String,
        token: String?,
        width: Int = 400
    ) -> URL? {
        guard
            let base,
            var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        else { return nil }

        components.path = "/api/items/\(itemId)/cover"

        var items: [URLQueryItem] = [
            URLQueryItem(name: "width", value: "\(width)")
        ]
        if let token {
            items.append(URLQueryItem(name: "token", value: token))
        }
        components.queryItems = items

        return components.url
    }
}

