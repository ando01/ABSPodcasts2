import SwiftUI

struct ContentView: View {
    @EnvironmentObject var playerManager: PlayerManager
    
    @State private var client: ABSClient?
    @State private var isConnected = false
    
    var body: some View {
        Group {
            if let client, isConnected {
                HomeView(client: client)
            } else {
                LoginView(isConnected: $isConnected, client: $client)
            }
        }
        .sheet(isPresented: $playerManager.isPresented) {
            NowPlayingView()
                .environmentObject(playerManager)
        }
    }
}

