// MusicPauser/MQTTTopics.swift
import Foundation

enum MQTTTopics {
    // MARK: - Topic builders

    static func availability(base: String) -> String     { "\(base)/availability" }
    static func micState(base: String) -> String         { "\(base)/mic/state" }
    static func playerState(base: String) -> String      { "\(base)/player/state" }
    static func playerAttributes(base: String) -> String { "\(base)/player/attributes" }
    static func command(base: String) -> String          { "\(base)/command" }

    // MARK: - Payload helpers

    static func micPayload(_ inUse: Bool) -> String {
        inUse ? "ON" : "OFF"
    }

    static func playerStatePayload(_ playing: Bool) -> String {
        playing ? "playing" : "stopped"
    }

    static func playerAttributesPayload(_ player: PlayerKind?) -> String {
        if let p = player { return "{\"player\":\"\(p.rawValue)\"}" }
        return "{\"player\":null}"
    }

    // MARK: - Home Assistant discovery messages

    /// Returns (topic, payload) pairs for all HA MQTT discovery configs.
    /// All should be published QoS 1, retain.
    static func discoveryMessages(settings: MQTTSettings) -> [(topic: String, payload: String)] {
        let base   = settings.baseTopic
        let avail  = availability(base: base)
        let dev    = settings.deviceName
        let device: [String: Any] = [
            "identifiers": [settings.clientID],
            "name":        "MusicPauser \(dev)",
            "manufacturer": "MusicPauser",
            "model":       "macOS Menu Bar App"
        ]

        func config(_ extra: [String: Any]) -> String {
            var d: [String: Any] = [
                "availability_topic":      avail,
                "payload_available":       "online",
                "payload_not_available":   "offline",
                "device":                  device
            ]
            extra.forEach { d[$0] = $1 }
            return jsonString(d)
        }

        let safeID = dev.lowercased()
            .unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "_" }
            .reduce("") { $0 + String($1) }

        return [
            // Binary sensor: mic
            (
                topic: "homeassistant/binary_sensor/\(safeID)_mic/config",
                payload: config([
                    "name":         "Microphone In Use",
                    "unique_id":    "\(safeID)_mic",
                    "state_topic":  micState(base: base),
                    "payload_on":   "ON",
                    "payload_off":  "OFF",
                    "device_class": "sound",
                    "icon":         "mdi:microphone"
                ])
            ),
            // Sensor: player state
            (
                topic: "homeassistant/sensor/\(safeID)_player/config",
                payload: config([
                    "name":                   "Music Player",
                    "unique_id":              "\(safeID)_player",
                    "state_topic":            playerState(base: base),
                    "json_attributes_topic":  playerAttributes(base: base),
                    "icon":                   "mdi:music"
                ])
            ),
            // Select: playback command
            (
                topic: "homeassistant/select/\(safeID)_command/config",
                payload: config([
                    "name":          "Playback Command",
                    "unique_id":     "\(safeID)_command",
                    "command_topic": command(base: base),
                    "options":       ["play", "pause", "stop", "toggle"],
                    "icon":          "mdi:play-circle-outline"
                ])
            )
        ]
    }

    // MARK: - JSON helper

    private static func jsonString(_ value: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value),
              let str  = String(data: data, encoding: .utf8) else { return "{}" }
        return str
    }
}
