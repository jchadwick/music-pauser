import SwiftUI
import os

@MainActor
final class AppState: ObservableObject {

    // MARK: - Published state

    @Published private(set) var micInUse: Bool = false
    @Published private(set) var isMusicPlaying: Bool = false
    @Published private(set) var lastAction: String = "None"

    // MARK: - Persisted preferences

    @AppStorage("autoPause")     var autoPause:     Bool = true
    @AppStorage("autoResume")    var autoResume:    Bool = true
    @AppStorage("launchAtLogin") var launchAtLogin: Bool = false

    // MARK: - Private

    private let micMonitor  = MicMonitor()
    private let music       = MusicController()
    private let logger      = Logger(subsystem: "com.jchadwick.musicpauser", category: "AppState")

    /// Did *we* cause the current Music pause? Only resume if true.
    private var wePaused: Bool = false

    private var musicNotificationObserver: NSObjectProtocol?

    // MARK: - Init

    init() {
        logger.notice("AppState.init() — starting up")

        // Seed isMusicPlaying from actual Music state (not just notifications).
        // This fixes the case where Music was already playing before we launched.
        let initiallyPlaying = music.isPlaying()
        isMusicPlaying = initiallyPlaying
        logger.notice("Initial Music state: isMusicPlaying=\(initiallyPlaying)")

        // Observe Apple Music player state changes via distributed notifications.
        musicNotificationObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.iTunes.playerInfo"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                self?.handlePlayerInfoNotification(notification)
            }
        }

        micMonitor.onChange = { [weak self] inUse in
            // MicMonitor dispatches to main queue already.
            self?.handleMicChange(inUse: inUse)
        }
        micMonitor.start()

        logger.notice("AppState.init() — complete. autoPause=\(self.autoPause) autoResume=\(self.autoResume)")
    }

    deinit {
        if let obs = musicNotificationObserver {
            DistributedNotificationCenter.default().removeObserver(obs)
        }
        micMonitor.stop()
    }

    // MARK: - Computed

    var statusText: String {
        micInUse ? "Microphone: ACTIVE" : "Microphone: idle"
    }

    // MARK: - Login item

    func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLogin = enabled
        if enabled {
            LoginItem.register()
        } else {
            LoginItem.unregister()
        }
    }

    // MARK: - Distributed notification handler

    private func handlePlayerInfoNotification(_ notification: Notification) {
        let rawState = notification.userInfo?["Player State"] as? String ?? "(nil)"
        logger.notice("Music playerInfo notification: Player State = '\(rawState)'")

        let nowPlaying = rawState == "Playing"
        let wasPlaying = isMusicPlaying
        isMusicPlaying = nowPlaying

        logger.notice("isMusicPlaying: \(wasPlaying) → \(nowPlaying)  micInUse=\(self.micInUse)  wePaused=\(self.wePaused)")

        // User manually resumed while mic is active → we shouldn't auto-resume again later.
        if !wasPlaying && nowPlaying && micInUse {
            logger.notice("User manually resumed Music while mic active — clearing wePaused")
            wePaused = false
        }

        // User manually paused while mic is active → don't auto-resume when mic stops.
        if wasPlaying && !nowPlaying && micInUse {
            logger.notice("User manually paused Music while mic active — clearing wePaused")
            wePaused = false
        }
    }

    // MARK: - Mic change handler

    private func handleMicChange(inUse: Bool) {
        logger.notice("handleMicChange(inUse: \(inUse)) — current micInUse=\(self.micInUse) isMusicPlaying=\(self.isMusicPlaying) wePaused=\(self.wePaused) autoPause=\(self.autoPause) autoResume=\(self.autoResume)")

        guard micInUse != inUse else {
            logger.notice("handleMicChange: state unchanged — ignoring")
            return
        }
        micInUse = inUse

        if inUse {
            // Re-query actual Music state in case we missed a notification.
            let actuallyPlaying = music.isPlaying()
            if actuallyPlaying != isMusicPlaying {
                logger.notice("isMusicPlaying cache was stale: cached=\(self.isMusicPlaying) actual=\(actuallyPlaying) — correcting")
                isMusicPlaying = actuallyPlaying
            }

            guard autoPause else {
                logger.notice("handleMicChange: mic active but autoPause=false — skipping pause")
                lastAction = "Mic active — auto-pause disabled"
                return
            }
            guard music.isRunning() else {
                logger.notice("handleMicChange: mic active but Music not running — skipping pause")
                lastAction = "Mic active — Music not running"
                return
            }
            guard isMusicPlaying else {
                logger.notice("handleMicChange: mic active but Music not playing — skipping pause")
                lastAction = "Mic active — Music already paused"
                return
            }

            logger.notice("handleMicChange: mic active + Music playing → PAUSING")
            music.pause()
            wePaused = true
            isMusicPlaying = false
            lastAction = "Paused Music at \(formattedTime())"

        } else {
            logger.notice("handleMicChange: mic released — wePaused=\(self.wePaused) autoResume=\(self.autoResume) isMusicPlaying=\(self.isMusicPlaying)")
            defer { wePaused = false }

            guard autoResume else {
                logger.notice("handleMicChange: mic released but autoResume=false — not resuming")
                lastAction = "Mic released — auto-resume disabled"
                return
            }
            guard wePaused else {
                logger.notice("handleMicChange: mic released but wePaused=false — Music was not paused by us")
                lastAction = "Mic released — Music not paused by us"
                return
            }
            guard !isMusicPlaying else {
                logger.notice("handleMicChange: mic released but isMusicPlaying=true — user already resumed manually")
                lastAction = "Mic released — user already resumed"
                return
            }
            guard music.isRunning() else {
                logger.notice("handleMicChange: mic released but Music not running — skipping resume")
                lastAction = "Mic released — Music not running"
                return
            }

            logger.notice("handleMicChange: mic released + wePaused → RESUMING")
            music.play()
            isMusicPlaying = true
            lastAction = "Resumed Music at \(formattedTime())"
        }
    }

    private func formattedTime() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: Date())
    }
}
