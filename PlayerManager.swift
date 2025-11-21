import Foundation
import Combine
import SwiftUI

final class PlayerManager: ObservableObject {
    @Published var currentEpisode: ABSClient.Episode?
    @Published var audioURL: URL?
    @Published var artworkURL: URL?

    /// When true, the full NowPlaying sheet is visible.
    @Published var isPresented: Bool = false

    /// True when there is something “loaded” in the player
    var isActive: Bool {
        currentEpisode != nil && audioURL != nil
    }

    /// Start playback for an episode and show the full player sheet
    func start(episode: ABSClient.Episode, audioURL: URL, artworkURL: URL?) {
        self.currentEpisode = episode
        self.audioURL = audioURL
        self.artworkURL = artworkURL
        self.isPresented = true
    }

    /// Hide the sheet but keep the mini-player visible
    func minimize() {
        isPresented = false
    }

    /// Clear everything (no mini-player, no sheet)
    func stop() {
        currentEpisode = nil
        audioURL = nil
        artworkURL = nil
        isPresented = false
    }
}

