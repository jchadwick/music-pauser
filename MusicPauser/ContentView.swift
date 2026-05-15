import SwiftUI

struct ContentView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        // Status section
        Text(appState.statusText)
            .fontWeight(.medium)

        Text("Music: \(appState.isMusicPlaying ? "playing" : "paused/stopped")")
            .foregroundStyle(.secondary)

        Text("Last action: \(appState.lastAction)")
            .foregroundStyle(.secondary)
            .font(.caption)

        Divider()

        Toggle("Auto-pause Apple Music", isOn: $appState.autoPause)
        Toggle("Auto-resume when mic released", isOn: $appState.autoResume)

        Divider()

        Toggle("Launch at Login", isOn: Binding(
            get: { appState.launchAtLogin },
            set: { appState.setLaunchAtLogin($0) }
        ))

        Divider()

        Button("Quit MusicPauser") {
            NSApplication.shared.terminate(nil)
        }
    }
}
