import Foundation
import Combine

struct PlaybackSettings: Codable {
    var skipBackSeconds: Int = 15
    var skipForwardSeconds: Int = 30
    var defaultSpeed: Float = 1.0
    var allowedSpeeds: [Float] = [1.0, 1.2, 1.5, 1.75, 2.0, 3.0]
}

final class PlaybackSettingsViewModel: ObservableObject {
    @Published var settings: PlaybackSettings {
        didSet { save() }
    }

    private let key = "PlaybackSettings"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode(PlaybackSettings.self, from: data) {
            self.settings = decoded
        } else {
            self.settings = PlaybackSettings()
        }
    }

    var allowedSkipValues: [Int] { [5, 10, 20, 30, 40, 50] }

    private func save() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

