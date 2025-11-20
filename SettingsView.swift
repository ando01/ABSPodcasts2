import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var playbackSettings: PlaybackSettingsViewModel

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Skip Durations")) {
                    Picker("Skip Back", selection: $playbackSettings.settings.skipBackSeconds) {
                        ForEach(playbackSettings.allowedSkipValues, id: \.self) { value in
                            Text("\(value) seconds").tag(value)
                        }
                    }

                    Picker("Skip Forward", selection: $playbackSettings.settings.skipForwardSeconds) {
                        ForEach(playbackSettings.allowedSkipValues, id: \.self) { value in
                            Text("\(value) seconds").tag(value)
                        }
                    }
                }

                Section(header: Text("Playback Speed")) {
                    Picker("Default Speed", selection: $playbackSettings.settings.defaultSpeed) {
                        ForEach(playbackSettings.settings.allowedSpeeds, id: \.self) { speed in
                            Text(String(format: "%.2gx", speed))
                                .tag(speed)
                        }
                    }
                }

                Section {
                    Button(role: .destructive) {
                        resetToDefaults()
                    } label: {
                        Text("Reset Playback Settings")
                    }
                } footer: {
                    Text("These options control the skip buttons and default playback speed used in the player.")
                }
            }
            .navigationTitle("Settings")
        }
    }

    private func resetToDefaults() {
        playbackSettings.settings = PlaybackSettings() // resets to struct defaults
    }
}

#Preview {
    SettingsView()
        .environmentObject(PlaybackSettingsViewModel())
}

