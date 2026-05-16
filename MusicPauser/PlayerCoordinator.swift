import AppKit
import os

private struct PlayerState {
    var isPlaying: Bool = false
    var pausedByUs: Bool = false
}

@MainActor
final class PlayerCoordinator {
    private let logger = Logger(subsystem: "com.jchadwick.musicpauser", category: "PlayerCoordinator")

    var autoPause:  Bool = true
    var autoResume: Bool = true

    var onPlaybackStateChanged: ((_ anyPlaying: Bool, _ activePlayer: PlayerKind?) -> Void)?
    var onAction: ((String) -> Void)?

    private let controllers: [any PlayerController]
    private var states: [PlayerKind: PlayerState] = [:]
    private var notificationObservers: [NSObjectProtocol] = []
    private var terminationObserver: NSObjectProtocol?

    init(controllers: [any PlayerController] = [MusicController(), SpotifyController()]) {
        self.controllers = controllers
        for c in controllers {
            states[c.kind] = PlayerState(isPlaying: c.isPlaying(), pausedByUs: false)
        }
        subscribeToPlayerNotifications()
        subscribeToTerminationNotifications()
    }

    deinit {
        for obs in notificationObservers { DistributedNotificationCenter.default().removeObserver(obs) }
        if let obs = terminationObserver { NSWorkspace.shared.notificationCenter.removeObserver(obs) }
    }

    var anyPlaying: Bool { states.values.contains { $0.isPlaying } }
    var activePlayerKind: PlayerKind? { controllers.first { states[$0.kind]?.isPlaying == true }?.kind }

    func handleMicBecameActive() {
        for c in controllers { states[c.kind]?.isPlaying = c.isPlaying() }
        guard autoPause else { log("Mic active — auto-pause disabled"); return }

        var pausedNames: [String] = []
        for c in controllers {
            guard states[c.kind]?.isPlaying == true else { continue }
            c.pause()
            states[c.kind]?.isPlaying = false
            states[c.kind]?.pausedByUs = true
            pausedNames.append(c.kind.displayName)
        }
        if pausedNames.isEmpty { log("Mic active — no players were playing") }
        else { log("Paused \(pausedNames.joined(separator: " & ")) at \(formattedTime())") }
        notifyPlaybackChanged()
    }

    func handleMicBecameInactive() {
        defer { for kind in states.keys { states[kind]?.pausedByUs = false } }
        guard autoResume else { log("Mic released — auto-resume disabled"); return }

        var resumedNames: [String] = []
        for c in controllers {
            guard states[c.kind]?.pausedByUs == true else { continue }
            guard !(states[c.kind]?.isPlaying ?? false) else { continue }
            guard c.isRunning() else { continue }
            c.play()
            states[c.kind]?.isPlaying = true
            resumedNames.append(c.kind.displayName)
        }
        if resumedNames.isEmpty { log("Mic released — nothing to resume") }
        else { log("Resumed \(resumedNames.joined(separator: " & ")) at \(formattedTime())") }
        notifyPlaybackChanged()
    }

    private func subscribeToPlayerNotifications() {
        let musicObs = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.iTunes.playerInfo"),
            object: nil, queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in self?.handleAppleMusicNotification(notification) }
        }
        notificationObservers.append(musicObs)

        let spotifyObs = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil, queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in self?.handleSpotifyNotification(notification) }
        }
        notificationObservers.append(spotifyObs)
    }

    private func handleAppleMusicNotification(_ notification: Notification) {
        let rawState = notification.userInfo?["Player State"] as? String ?? ""
        updatePlaybackState(for: .appleMusic, nowPlaying: rawState == "Playing")
    }

    private func handleSpotifyNotification(_ notification: Notification) {
        let rawState = notification.userInfo?["Player State"] as? String ?? ""
        updatePlaybackState(for: .spotify, nowPlaying: rawState == "Playing")
    }

    private func updatePlaybackState(for kind: PlayerKind, nowPlaying: Bool) {
        let wasPlaying = states[kind]?.isPlaying ?? false
        states[kind]?.isPlaying = nowPlaying
        if wasPlaying != nowPlaying { states[kind]?.pausedByUs = false }
        notifyPlaybackChanged()
    }

    private func subscribeToTerminationNotifications() {
        terminationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in self?.handleAppTermination(notification) }
        }
    }

    private func handleAppTermination(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleID = app.bundleIdentifier else { return }
        
        guard let controller = controllers.first(where: { $0.bundleIdentifier == bundleID }) else { return }
        let kind = controller.kind
        states[kind]?.isPlaying = false
        states[kind]?.pausedByUs = false
        notifyPlaybackChanged()
    }

    private func notifyPlaybackChanged() { onPlaybackStateChanged?(anyPlaying, activePlayerKind) }
    private func log(_ message: String) { logger.notice("\(message)"); onAction?(message) }
    private func formattedTime() -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f.string(from: Date())
    }
}
