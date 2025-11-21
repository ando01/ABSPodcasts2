import SwiftUI

@main
struct ABSPodcastsApp: App {

    @StateObject private var playbackSettings = PlaybackSettingsViewModel()
    @StateObject private var playerManager = PlayerManager()

    init() {
        AudioSessionManager.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(playbackSettings)
                .environmentObject(playerManager)      // 👈 add this
        }
    }
}
