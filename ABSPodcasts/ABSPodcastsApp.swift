//
//  ABSPodcastsApp.swift
//  ABSPodcasts
//
//  Created by Andrew Melton on 11/19/25.
//

import SwiftUI

@main
struct ABSPodcastsApp: App {

    init() {
        AudioSessionManager.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

