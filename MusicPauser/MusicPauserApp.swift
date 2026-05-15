import SwiftUI

@main
struct MusicPauserApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            ContentView(appState: appState)
        } label: {
            // mic.fill = idle (good), mic.slash.fill = mic in use (bad/red)
            Image(systemName: appState.micInUse ? "mic.slash.fill" : "mic.fill")
                .symbolRenderingMode(.monochrome)
        }
        .menuBarExtraStyle(.menu)
    }
}
