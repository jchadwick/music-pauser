// MusicPauser/MQTTSettingsView.swift
import SwiftUI

struct MQTTSettingsView: View {
    @ObservedObject var settings: MQTTSettings
    @ObservedObject var service:  MQTTService

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("Connection") {
                Toggle("Enable MQTT", isOn: $settings.enabled)

                TextField("Broker Host", text: $settings.host)
                    .disableAutocorrection(true)

                HStack {
                    Text("Port")
                    Spacer()
                    TextField("1883", value: $settings.port, format: .number)
                        .frame(width: 80)
                        .multilineTextAlignment(.trailing)
                }

                Toggle("Use TLS / SSL", isOn: $settings.useTLS)
            }

            Section("Authentication") {
                TextField("Username (optional)", text: $settings.username)
                    .disableAutocorrection(true)

                SecureField("Password (stored in Keychain)", text: $settings.password)
            }

            Section("Identity") {
                TextField("Client ID", text: $settings.clientID)
                    .disableAutocorrection(true)

                TextField("Device Name", text: $settings.deviceName)
                    .disableAutocorrection(true)
                    .help("Used in MQTT topics: {prefix}/{device}/…")

                TextField("Topic Prefix", text: $settings.topicPrefix)
                    .disableAutocorrection(true)
            }

            Section("Home Assistant") {
                Toggle("Publish HA Discovery messages", isOn: $settings.publishDiscovery)
                if settings.enabled && !settings.host.isEmpty {
                    Text("Base topic: \(settings.baseTopic)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Status") {
                HStack {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    Text(service.connectionState.displayText)
                    Spacer()
                }
                if let err = service.lastError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section {
                HStack {
                    Button("Reconnect") {
                        service.stop()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            service.start()
                        }
                    }
                    .disabled(!settings.isConfigured)

                    Spacer()

                    Button("Done") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 420, minHeight: 500)
        .padding()
    }

    private var statusColor: Color {
        switch service.connectionState {
        case .connected:     return .green
        case .connecting:    return .yellow
        case .reconnecting:  return .orange
        default:             return Color(nsColor: .secondaryLabelColor)
        }
    }
}
