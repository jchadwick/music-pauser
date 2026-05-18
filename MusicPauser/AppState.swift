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

    let mqttSettings = MQTTSettings()
    private(set) lazy var mqttService = MQTTService(settings: mqttSettings)

    private let micMonitor  = MicMonitor()
    private let coordinator = PlayerCoordinator()
    private let logger      = Logger(subsystem: "com.jchadwick.musicpauser", category: "AppState")

    init() {
        coordinator.autoPause  = autoPause
        coordinator.autoResume = autoResume
        isAnyPlaying = coordinator.anyPlaying
        activePlayer = coordinator.activePlayerKind

        coordinator.onPlaybackStateChanged = { [weak self] anyPlaying, active in
            guard let self else { return }
            self.isAnyPlaying = anyPlaying
            self.activePlayer = active
            self.mqttService.publishState(micInUse: self.micInUse, anyPlaying: anyPlaying, activePlayer: active)
        }
        coordinator.onAction = { [weak self] message in self?.lastAction = message }

        micMonitor.onChange = { [weak self] inUse in self?.handleMicChange(inUse: inUse) }
        micMonitor.start()

        mqttService.onCommand = { [weak self] cmd in self?.handleMQTTCommand(cmd) }
        mqttService.start()
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
        mqttService.publishState(micInUse: inUse, anyPlaying: isAnyPlaying, activePlayer: activePlayer)
        if inUse { coordinator.handleMicBecameActive() }
        else { coordinator.handleMicBecameInactive() }
    }

    private func handleMQTTCommand(_ cmd: MQTTCommand) {
        switch cmd {
        case .play(let player):   coordinator.play(player: player)
        case .pause(let player):  coordinator.pause(player: player)
        case .stop(let player):   coordinator.stop(player: player)
        case .toggle(let player): coordinator.toggle(player: player)
        }
    }
}
