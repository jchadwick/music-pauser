import SwiftUI

struct ContentView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        Text(appState.statusText).fontWeight(.medium)
        playerStatusText.foregroundStyle(.secondary)
        Text("Last action: \(appState.lastAction)").foregroundStyle(.secondary).font(.caption)
        Divider()
        Toggle("Auto-pause music", isOn: $appState.autoPause)
        Toggle("Auto-resume when mic released", isOn: $appState.autoResume)
        Divider()
        Toggle("Launch at Login", isOn: Binding(
            get: { appState.launchAtLogin },
            set: { appState.setLaunchAtLogin($0) }
        ))
        Divider()
        Button("Quit MusicPauser") { NSApplication.shared.terminate(nil) }
    }

    @ViewBuilder
    private var playerStatusText: some View {
        if let active = appState.activePlayer {
            Text("Active: \(active.displayName)")
        } else {
            Text("Active: none")
        }
    }
}
