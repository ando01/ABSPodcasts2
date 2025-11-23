import Foundation

extension URL {
    /// Build the official Audiobookshelf cover URL:
    ///   <base>/api/items/<id>/cover?width=400&token=...
    static func absCoverURL(
        base: URL?,
        itemId: String,
        token: String?,
        width: Int = 400
    ) -> URL? {
        guard let base else { return nil }

        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        components?.path = "/api/items/\(itemId)/cover"

        var items: [URLQueryItem] = [
            URLQueryItem(name: "width", value: "\(width)")
        ]
        if let token {
            items.append(URLQueryItem(name: "token", value: token))
        }
        components?.queryItems = items

        return components?.url
    }
}

