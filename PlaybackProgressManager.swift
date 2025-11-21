import Foundation

/// Manages playback progress for episodes/audiobooks
class PlaybackProgressManager {
    static let shared = PlaybackProgressManager()
    
    private let userDefaults = UserDefaults.standard
    private let progressKey = "episodePlaybackProgress"
    private let lastPlayedKey = "lastPlayedItem"
    
    struct Progress: Codable {
        let episodeId: String
        let currentTime: Double
        let duration: Double
        let lastPlayed: Date
        
        var progressPercentage: Double {
            guard duration > 0 else { return 0 }
            return (currentTime / duration) * 100
        }
        
        var isCompleted: Bool {
            guard duration > 0 else { return false }
            // Consider completed if within last 3 seconds
            return currentTime >= max(duration - 3, 0)
        }
    }
    
    struct LastPlayedItem: Codable {
        let episodeId: String
        let title: String
        let streamURLString: String
        let artworkURLString: String?
        let lastPlayed: Date
    }
    
    private init() {}
    
    // MARK: - Save Progress
    
    func saveProgress(episodeId: String, currentTime: Double, duration: Double) {
        var allProgress = loadAllProgress()
        
        let progress = Progress(
            episodeId: episodeId,
            currentTime: currentTime,
            duration: duration,
            lastPlayed: Date()
        )
        
        allProgress[episodeId] = progress
        
        if let encoded = try? JSONEncoder().encode(allProgress) {
            userDefaults.set(encoded, forKey: progressKey)
            // print("💾 Saved progress for \(episodeId)")
        }
    }
    
    // MARK: - Load Progress
    
    func loadProgress(for episodeId: String) -> Progress? {
        let allProgress = loadAllProgress()
        return allProgress[episodeId]
    }
    
    func loadAllProgress() -> [String: Progress] {
        guard let data = userDefaults.data(forKey: progressKey),
              let decoded = try? JSONDecoder().decode([String: Progress].self, from: data) else {
            return [:]
        }
        return decoded
    }
    
    // MARK: - Clear Progress
    
    func clearProgress(for episodeId: String) {
        var allProgress = loadAllProgress()
        allProgress.removeValue(forKey: episodeId)
        
        if let encoded = try? JSONEncoder().encode(allProgress) {
            userDefaults.set(encoded, forKey: progressKey)
            // print("🗑️ Cleared progress for \(episodeId)")
        }
    }
    
    // MARK: - Last Played Item (for "Pick up where you left off")
    
    func saveLastPlayed(
        episodeId: String,
        title: String,
        streamURLString: String,
        artworkURLString: String?
    ) {
        let latest = LastPlayedItem(
            episodeId: episodeId,
            title: title,
            streamURLString: streamURLString,
            artworkURLString: artworkURLString,
            lastPlayed: Date()
        )
        
        if let encoded = try? JSONEncoder().encode(latest) {
            userDefaults.set(encoded, forKey: lastPlayedKey)
        }
    }
    
    func loadLastPlayed() -> LastPlayedItem? {
        guard let data = userDefaults.data(forKey: lastPlayedKey),
              let decoded = try? JSONDecoder().decode(LastPlayedItem.self, from: data) else {
            return nil
        }
        return decoded
    }
    
    func clearLastPlayed() {
        userDefaults.removeObject(forKey: lastPlayedKey)
    }
    
    // MARK: - Formatting
    
    func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
}

