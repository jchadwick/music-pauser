import SwiftUI
import os

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var micInUse:        Bool        = false
    @Published private(set) var isAnyPlaying:    Bool        = false
    @Published private(set) var activePlayer:    PlayerKind? = nil
    @Published private(set) var lastAction:      String      = "None"

    @AppStorage("autoPause")     var autoPause:     Bool = true  { didSet { coordinator.autoPause  = autoPause  } }
    @AppStorage("autoResume")    var autoResume:    Bool = true  { didSet { coordinator.autoResume = autoResume } }
    @AppStorage("launchAtLogin") var launchAtLogin: Bool = false

    private let micMonitor  = MicMonitor()
    private let coordinator = PlayerCoordinator()
    private let logger      = Logger(subsystem: "com.jchadwick.musicpauser", category: "AppState")

    init() {
        coordinator.autoPause  = autoPause
        coordinator.autoResume = autoResume
        isAnyPlaying = coordinator.anyPlaying
        activePlayer = coordinator.activePlayerKind

        coordinator.onPlaybackStateChanged = { [weak self] anyPlaying, active in
            self?.isAnyPlaying = anyPlaying
            self?.activePlayer = active
        }
        coordinator.onAction = { [weak self] message in self?.lastAction = message }

        micMonitor.onChange = { [weak self] inUse in self?.handleMicChange(inUse: inUse) }
        micMonitor.start()
    }
    deinit { micMonitor.stop() }

    var statusText: String { micInUse ? "Microphone: ACTIVE" : "Microphone: idle" }

    func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLogin = enabled
        if enabled { LoginItem.register() } else { LoginItem.unregister() }
    }

    private func handleMicChange(inUse: Bool) {
        guard micInUse != inUse else { return }
        micInUse = inUse
        if inUse { coordinator.handleMicBecameActive() }
        else { coordinator.handleMicBecameInactive() }
    }
}
