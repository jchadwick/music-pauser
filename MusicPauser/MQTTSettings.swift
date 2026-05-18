// MusicPauser/MQTTSettings.swift
import Foundation
import Security
import SwiftUI

// MARK: - Keychain helpers

private enum Keychain {
    private static let service = "com.jchadwick.musicpauser.mqtt"
    private static let account = "mqtt-password"

    static func save(_ password: String) {
        let data = Data(password.utf8)
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData] = data
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    static func load() -> String? {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData:  true,
            kSecMatchLimit:  kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete() {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - MQTTSettings

final class MQTTSettings: ObservableObject {

    // MARK: UserDefaults-backed settings

    @AppStorage("mqtt.enabled")          var enabled:          Bool   = false
    @AppStorage("mqtt.host")             var host:             String = ""
    @AppStorage("mqtt.port")             var port:             Int    = 1883
    @AppStorage("mqtt.username")         var username:         String = ""
    @AppStorage("mqtt.clientID")         var clientID:         String = MQTTSettings.makeClientID()
    @AppStorage("mqtt.topicPrefix")      var topicPrefix:      String = "musicpauser"
    @AppStorage("mqtt.deviceName")       var deviceName:       String = MQTTSettings.makeDeviceName()
    @AppStorage("mqtt.useTLS")           var useTLS:           Bool   = false
    @AppStorage("mqtt.publishDiscovery") var publishDiscovery: Bool   = true

    // MARK: Keychain-backed password

    /// In-memory cache — read from Keychain once at init.
    @Published var password: String = "" {
        didSet {
            if password.isEmpty { Keychain.delete() }
            else                { Keychain.save(password) }
        }
    }

    init() {
        password = Keychain.load() ?? ""
    }

    // MARK: Computed helpers

    var baseTopic: String {
        let prefix = topicPrefix.trimmingCharacters(in: .init(charactersIn: "/ \t\n\r"))
        let device = deviceName.trimmingCharacters(in: .init(charactersIn: "/ \t\n\r"))
        return "\(prefix.isEmpty ? "musicpauser" : prefix)/\(device.isEmpty ? "mac" : device)"
    }

    var resolvedHost: String { host.trimmingCharacters(in: .whitespacesAndNewlines) }
    var resolvedPort: UInt16 { UInt16(max(1, min(65535, port))) }
    var resolvedUsername: String? { username.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
    var resolvedPassword: String? { password.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
    var isConfigured: Bool { enabled && !resolvedHost.isEmpty }

    // MARK: Default generators

    static func makeClientID() -> String {
        "musicpauser-\(Host.current().localizedName?.replacingOccurrences(of: " ", with: "-") ?? String(UUID().uuidString.prefix(8)))"
    }

    static func makeDeviceName() -> String {
        (Host.current().localizedName ?? "mac")
            .replacingOccurrences(of: " ", with: "-")
            .lowercased()
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
