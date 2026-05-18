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
        Button("MQTT Settings…") {
            NSApp.activate(ignoringOtherApps: true)
            if let window = NSApp.windows.first(where: { $0.title == "MQTT Settings" }) {
                window.makeKeyAndOrderFront(nil)
            } else {
                openMQTTSettingsWindow()
            }
        }
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

    private func openMQTTSettingsWindow() {
        let view = MQTTSettingsView(settings: appState.mqttSettings, service: appState.mqttService)
        let controller = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: controller)
        window.title = "MQTT Settings"
        window.styleMask = [.titled, .closable, .resizable]
        window.setContentSize(NSSize(width: 460, height: 540))
        window.center()
        window.makeKeyAndOrderFront(nil)
    }
}

