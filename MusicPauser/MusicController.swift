import AppKit
import os

/// Controls Apple Music playback via AppleScript.
/// All methods must be called on the main thread (AppState is @MainActor, so guaranteed).
final class MusicController {

    private let logger = Logger(subsystem: "com.jchadwick.musicpauser", category: "MusicController")

    // MARK: - Public API

    /// Returns true if Music.app is currently running (without launching it).
    func isRunning() -> Bool {
        let running = NSWorkspace.shared.runningApplications
            .contains { $0.bundleIdentifier == "com.apple.Music" }
        logger.notice("isRunning() → \(running)")
        return running
    }

    /// Returns true if Music is currently playing. Calls AppleScript — only call when isRunning() is true.
    func isPlaying() -> Bool {
        dispatchPrecondition(condition: .onQueue(.main))
        guard isRunning() else {
            logger.notice("isPlaying() → false (Music not running)")
            return false
        }
        // AppleScript: player state returns a constant; we compare to 'playing'
        let source = """
        tell application "Music"
            if it is running then
                return (player state as string)
            end if
        end tell
        """
        guard let script = NSAppleScript(source: source) else {
            logger.error("isPlaying(): failed to compile AppleScript")
            return false
        }
        var errorDict: NSDictionary?
        let descriptor = script.executeAndReturnError(&errorDict)
        if let errorDict {
            logger.error("isPlaying() AppleScript error: \(errorDict)")
            return false
        }
        let stateStr = descriptor.stringValue ?? ""
        let playing = stateStr.lowercased().contains("playing")
        logger.notice("isPlaying() → \(playing) (raw player state: '\(stateStr)')")
        return playing
    }

    /// Pauses Music. No-op if Music is not running.
    func pause() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard isRunning() else {
            logger.notice("pause() skipped — Music not running")
            return
        }
        logger.notice("pause() — sending pause command to Music")
        run("tell application \"Music\" to pause")
    }

    /// Resumes Music. No-op if Music is not running.
    func play() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard isRunning() else {
            logger.notice("play() skipped — Music not running")
            return
        }
        logger.notice("play() — sending play command to Music")
        run("tell application \"Music\" to play")
    }

    // MARK: - Private

    private func run(_ source: String) {
        guard let script = NSAppleScript(source: source) else {
            logger.error("Failed to compile AppleScript: \(source)")
            return
        }
        var errorDict: NSDictionary?
        script.executeAndReturnError(&errorDict)
        if let errorDict {
            logger.error("AppleScript execution error: \(errorDict)")
        }
    }
}
