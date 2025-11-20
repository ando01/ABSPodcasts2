import SwiftUI

@main
struct ABSPodcastsApp: App {
    @StateObject private var playbackSettings = PlaybackSettingsViewModel()

    init() {
        AudioSessionManager.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(playbackSettings)
        }
    }
}
