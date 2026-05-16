import AppKit
import os

final class SpotifyController: PlayerController {
    private let logger = Logger(subsystem: "com.jchadwick.musicpauser", category: "SpotifyController")
    let kind: PlayerKind = .spotify
    let bundleIdentifier: String = "com.spotify.client"

    func isRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleIdentifier }
    }
    func isPlaying() -> Bool {
        dispatchPrecondition(condition: .onQueue(.main))
        guard isRunning() else { return false }
        let source = """
        tell application "Spotify"
            if it is running then
                return (player state as string)
            end if
        end tell
        """
        guard let script = NSAppleScript(source: source) else { return false }
        var errorDict: NSDictionary?
        let descriptor = script.executeAndReturnError(&errorDict)
        if let errorDict { logger.error("isPlaying() AppleScript error: \(errorDict)"); return false }
        let stateStr = descriptor.stringValue ?? ""
        let playing = stateStr.lowercased().contains("playing")
        logger.notice("isPlaying() → \(playing) (raw: '\(stateStr)')")
        return playing
    }
    func pause() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard isRunning() else { return }
        run(#"tell application "Spotify" to pause"#)
    }
    func play() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard isRunning() else { return }
        run(#"tell application "Spotify" to play"#)
    }
    private func run(_ source: String) {
        guard let script = NSAppleScript(source: source) else { return }
        var errorDict: NSDictionary?
        script.executeAndReturnError(&errorDict)
        if let errorDict { logger.error("AppleScript error: \(errorDict)") }
    }
}
