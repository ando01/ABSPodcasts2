import SwiftUI

@main
struct ABSPodcastsApp: App {
    @StateObject var playerManager = PlayerManager()

    var body: some Scene {
        WindowGroup {
            ContentView()          // 👈 use whatever your main view is
                .environmentObject(playerManager)
        }
    }
}
