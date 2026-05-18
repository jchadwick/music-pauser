// MusicPauser/MQTTCommand.swift
import Foundation

/// Commands that arrive via MQTT on the `{base}/command` topic.
enum MQTTCommand: Equatable {
    case play(player: PlayerKind?)
    case pause(player: PlayerKind?)
    case stop(player: PlayerKind?)
    case toggle(player: PlayerKind?)

    var actionName: String {
        switch self {
        case .play:   return "play"
        case .pause:  return "pause"
        case .stop:   return "stop"
        case .toggle: return "toggle"
        }
    }

    var player: PlayerKind? {
        switch self {
        case .play(let p), .pause(let p), .stop(let p), .toggle(let p): return p
        }
    }

    /// Parses a raw MQTT payload string.
    ///
    /// Supported plain-text formats:
    ///   `play`              → play all players
    ///   `pause/spotify`     → pause Spotify only
    ///   `stop/appleMusic`   → stop Apple Music only
    ///   `toggle`            → toggle all
    ///
    /// Supported JSON format:
    ///   `{"action":"pause","player":"spotify"}`
    static func parse(_ payload: String) -> MQTTCommand? {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return parseJSON(trimmed) ?? parsePlaintext(trimmed)
    }

    private static func parseJSON(_ text: String) -> MQTTCommand? {
        guard let data = text.data(using: .utf8),
              let obj  = try? JSONSerialization.jsonObject(with: data),
              let dict = obj as? [String: Any] else { return nil }

        let verb = ((dict["action"] ?? dict["command"]) as? String ?? "").lowercased()
        let playerRaw = (dict["player"] as? String ?? "").lowercased()
        return make(verb: verb, playerRaw: playerRaw)
    }

    private static func parsePlaintext(_ text: String) -> MQTTCommand? {
        let parts = text.lowercased().components(separatedBy: CharacterSet(charactersIn: "/ :|"))
                        .filter { !$0.isEmpty }
        guard let verb = parts.first else { return nil }
        return make(verb: verb, playerRaw: parts.dropFirst().first ?? "")
    }

    private static func make(verb: String, playerRaw: String) -> MQTTCommand? {
        let player = parsePlayer(playerRaw)
        switch verb {
        case "play":   return .play(player: player)
        case "pause":  return .pause(player: player)
        case "stop":   return .stop(player: player)
        case "toggle": return .toggle(player: player)
        default:       return nil
        }
    }

    private static func parsePlayer(_ raw: String) -> PlayerKind? {
        switch raw {
        case "spotify":                           return .spotify
        case "applemusic", "apple_music",
             "apple-music", "music", "apple":     return .appleMusic
        default:                                  return nil
        }
    }
}
