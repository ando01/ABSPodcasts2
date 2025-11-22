import Foundation
import UIKit
import Combine

/// Simple singleton download manager for offline playback.
/// - Stores downloaded audio files in Documents
/// - Stores artwork images per id in Documents (fixed filenames)
/// - Persists a small JSON index for audio so downloads survive app restarts
final class DownloadManager: ObservableObject {
    static let shared = DownloadManager()

    /// id (episodeId / audiobookId) -> local audio file URL
    @Published private(set) var downloads: [String: URL] = [:]

    private let audioIndexFilename = "downloads_index.json"

    private init() {
        loadAudioIndex()
    }

    // MARK: - Public audio API

    func isDownloaded(id: String) -> Bool {
        downloads[id] != nil
    }

    func localURL(for id: String) -> URL? {
        downloads[id]
    }

    /// Download a remote audio URL and store it locally for the given id.
    func download(id: String, from remoteURL: URL) async throws {
        print("⬇️ [DownloadManager] Starting audio download for id=\(id) from \(remoteURL)")
        let (tempURL, _) = try await URLSession.shared.download(from: remoteURL)

        let destination = destinationURL(for: id, remoteURL: remoteURL)
        let fm = FileManager.default

        // Remove any previous file
        try? fm.removeItem(at: destination)
        try fm.moveItem(at: tempURL, to: destination)

        await MainActor.run {
            self.downloads[id] = destination
            self.saveAudioIndex()
            print("✅ [DownloadManager] Stored audio for id=\(id) at \(destination.path)")
        }
    }

    /// Delete a previously downloaded audio file AND its cached artwork for the given id.
    func delete(id: String) {
        if let local = downloads[id] {
            try? FileManager.default.removeItem(at: local)
            print("🗑️ [DownloadManager] Removed audio for id=\(id) at \(local.path)")
            downloads.removeValue(forKey: id)
            saveAudioIndex()
        }

        let artURL = artworkFileURL(for: id)
        if FileManager.default.fileExists(atPath: artURL.path) {
            try? FileManager.default.removeItem(at: artURL)
            print("🗑️ [DownloadManager] Removed artwork for id=\(id) at \(artURL.path)")
        }
    }

    // MARK: - Artwork API

    /// Download artwork image from a remote URL and cache it for this id.
    func storeArtwork(id: String, from remoteURL: URL) async {
        let dest = artworkFileURL(for: id)
        print("🎨 [DownloadManager] Storing artwork for id=\(id) from \(remoteURL) -> \(dest.path)")
        do {
            let (data, _) = try await URLSession.shared.data(from: remoteURL)
            try data.write(to: dest, options: [.atomic])
            print("✅ [DownloadManager] Artwork stored for id=\(id)")
        } catch {
            print("⚠️ [DownloadManager] Failed to store artwork for id=\(id): \(error)")
        }
    }

    /// Return a cached artwork UIImage for the given id, if available.
    func cachedArtworkImage(for id: String) -> UIImage? {
        let url = artworkFileURL(for: id)
        let exists = FileManager.default.fileExists(atPath: url.path)
        print("🔍 [DownloadManager] Checking cached artwork for id=\(id) at \(url.path) exists=\(exists)")

        guard exists,
              let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else {
            if exists {
                print("⚠️ [DownloadManager] File exists but could not decode image for id=\(id)")
            }
            return nil
        }

        print("✅ [DownloadManager] Loaded cached artwork for id=\(id)")
        return image
    }

    // MARK: - Paths

    private func documentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    /// Where we store the downloaded audio file.
    private func destinationURL(for id: String, remoteURL: URL) -> URL {
        let dir = documentsDirectory()
        let ext = remoteURL.pathExtension.isEmpty ? "mp3" : remoteURL.pathExtension
        return dir.appendingPathComponent("\(id).\(ext)")
    }

    /// Where we store the cached artwork image.
    private func artworkFileURL(for id: String) -> URL {
        let dir = documentsDirectory()
        // Single fixed extension — we only care that UIImage can decode it
        return dir.appendingPathComponent("\(id)_artwork.dat")
    }

    // MARK: - Audio index persistence

    private func saveAudioIndex() {
        let dir = documentsDirectory()
        let file = dir.appendingPathComponent(audioIndexFilename)

        let filenames = downloads.mapValues { $0.lastPathComponent }

        do {
            let data = try JSONEncoder().encode(filenames)
            try data.write(to: file, options: [.atomic])
        } catch {
            print("⚠️ [DownloadManager] Failed to save downloads index: \(error)")
        }
    }

    private func loadAudioIndex() {
        let dir = documentsDirectory()
        let file = dir.appendingPathComponent(audioIndexFilename)

        guard let data = try? Data(contentsOf: file) else { return }

        do {
            let filenames = try JSONDecoder().decode([String: String].self, from: data)
            var map: [String: URL] = [:]
            for (id, name) in filenames {
                let url = dir.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: url.path) {
                    map[id] = url
                }
            }
            downloads = map
            print("ℹ️ [DownloadManager] Loaded \(downloads.count) downloaded audio items from index")
        } catch {
            print("⚠️ [DownloadManager] Failed to load downloads index: \(error)")
        }
    }
}

