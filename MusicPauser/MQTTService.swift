// MusicPauser/MQTTService.swift
//
// Minimal MQTT 3.1.1 client built on Network.framework.
// Supports: CONNECT/CONNACK, PUBLISH QoS 0&1 / PUBACK,
//           SUBSCRIBE/SUBACK, PINGREQ/PINGRESP, DISCONNECT.
// I/O runs on a private DispatchQueue; state updates bridge to @MainActor.
//
import Foundation
import Network
import os

// ===========================================================================
// MARK: - Connection state (public)
// ===========================================================================

enum MQTTConnectionState: Equatable {
    case disabled
    case connecting
    case connected
    case reconnecting(attempt: Int)
    case disconnected

    var displayText: String {
        switch self {
        case .disabled:              return "Disabled"
        case .connecting:            return "Connecting…"
        case .connected:             return "Connected"
        case .reconnecting(let n):   return "Reconnecting (\(n))…"
        case .disconnected:          return "Disconnected"
        }
    }
}

// ===========================================================================
// MARK: - MQTTService (@MainActor)
// ===========================================================================

@MainActor
final class MQTTService: ObservableObject {

    @Published private(set) var connectionState: MQTTConnectionState = .disabled
    @Published private(set) var lastError: String?

    /// Called on MainActor when a command arrives on the command topic.
    var onCommand: ((MQTTCommand) -> Void)?

    private let settings: MQTTSettings
    private let logger   = Logger(subsystem: "com.jchadwick.musicpauser", category: "MQTTService")
    private let netQueue = DispatchQueue(label: "com.jchadwick.musicpauser.mqtt", qos: .utility)

    private var client:           MQTTRawClient?
    private var reconnectItem:    DispatchWorkItem?
    private var reconnectDelay:   TimeInterval = 2
    private var reconnectAttempt: Int = 0
    private var isStopped:        Bool = true

    // Cached state for re-publish on reconnect
    private var cachedMicInUse:    Bool         = false
    private var cachedAnyPlaying:  Bool         = false
    private var cachedActivePlayer: PlayerKind? = nil

    // MARK: - Init

    init(settings: MQTTSettings) {
        self.settings = settings
    }

    // MARK: - Public API

    func start() {
        guard settings.isConfigured else {
            connectionState = .disabled
            return
        }
        isStopped = false
        reconnectAttempt = 0
        reconnectDelay = 2
        connect(reason: "start")
    }

    func stop() {
        isStopped = true
        cancelReconnect()
        let c = client; client = nil
        netQueue.async {
            c?.disconnect(sendOffline: true)
        }
        connectionState = .disconnected
    }

    func publishState(micInUse: Bool, anyPlaying: Bool, activePlayer: PlayerKind?) {
        cachedMicInUse     = micInUse
        cachedAnyPlaying   = anyPlaying
        cachedActivePlayer = activePlayer
        guard case .connected = connectionState else { return }
        let base = settings.baseTopic
        let msgs: [(String, String, UInt8, Bool)] = [
            (MQTTTopics.micState(base: base),          MQTTTopics.micPayload(micInUse),             1, true),
            (MQTTTopics.playerState(base: base),       MQTTTopics.playerStatePayload(anyPlaying),   1, true),
            (MQTTTopics.playerAttributes(base: base),  MQTTTopics.playerAttributesPayload(anyPlaying: anyPlaying, activePlayer: activePlayer), 1, true)
        ]
        let c = client
        netQueue.async { msgs.forEach { c?.publish(topic: $0.0, payload: $0.1, qos: $0.2, retain: $0.3) } }
    }

    // MARK: - Private connection management

    private func connect(reason: String) {
        guard !isStopped, settings.isConfigured else { return }
        cancelReconnect()
        client?.disconnect(sendOffline: false)
        client = nil
        lastError = nil
        connectionState = reconnectAttempt == 0 ? .connecting : .reconnecting(attempt: reconnectAttempt)
        logger.notice("MQTT connect (\(reason, privacy: .public))")

        let cfg = MQTTRawClient.Config(
            host:          settings.resolvedHost,
            port:          settings.resolvedPort,
            useTLS:        settings.useTLS,
            clientID:      settings.clientID,
            username:      settings.resolvedUsername,
            password:      settings.resolvedPassword,
            keepAlive:     60,
            willTopic:     MQTTTopics.availability(base: settings.baseTopic),
            willPayload:   "offline",
            willQoS:       1,
            willRetain:    true
        )

        let raw = MQTTRawClient(config: cfg, queue: netQueue)

        raw.onConnected = { [weak self] in
            Task { @MainActor [weak self] in self?.handleConnected() }
        }
        raw.onDisconnected = { [weak self] expected, error in
            Task { @MainActor [weak self] in self?.handleDisconnected(expected: expected, error: error) }
        }
        raw.onMessage = { [weak self] topic, payload in
            Task { @MainActor [weak self] in self?.handleMessage(topic: topic, payload: payload) }
        }

        client = raw
        raw.start()
    }

    private func handleConnected() {
        connectionState = .connected
        reconnectAttempt = 0
        reconnectDelay = 2
        lastError = nil
        logger.notice("MQTT connected")

        let base = settings.baseTopic
        let c = client
        netQueue.async {
            c?.publish(topic: MQTTTopics.availability(base: base), payload: "online", qos: 1, retain: true)
            c?.subscribe(topic: MQTTTopics.command(base: base), qos: 1)
        }
        if settings.publishDiscovery {
            let msgs = MQTTTopics.discoveryMessages(settings: settings)
            let cl = client
            netQueue.async { msgs.forEach { cl?.publish(topic: $0.topic, payload: $0.payload, qos: 1, retain: true) } }
        }

        publishCachedState()
    }

    private func handleDisconnected(expected: Bool, error: String?) {
        client = nil
        if expected || isStopped || !settings.isConfigured {
            connectionState = settings.enabled ? .disconnected : .disabled
            return
        }
        lastError = error
        connectionState = .reconnecting(attempt: reconnectAttempt)
        scheduleReconnect()
    }

    private func handleMessage(topic: String, payload: String) {
        let expected = MQTTTopics.command(base: settings.baseTopic)
        guard topic == expected else { return }
        guard let cmd = MQTTCommand.parse(payload) else {
            logger.warning("Unrecognised command payload: \(payload)")
            return
        }
        onCommand?(cmd)
    }

    private func publishCachedState() {
        guard case .connected = connectionState else { return }
        let base = settings.baseTopic
        let msgs: [(String, String, UInt8, Bool)] = [
            (MQTTTopics.micState(base: base),         MQTTTopics.micPayload(cachedMicInUse),              1, true),
            (MQTTTopics.playerState(base: base),      MQTTTopics.playerStatePayload(cachedAnyPlaying),    1, true),
            (MQTTTopics.playerAttributes(base: base), MQTTTopics.playerAttributesPayload(anyPlaying: cachedAnyPlaying, activePlayer: cachedActivePlayer), 1, true)
        ]
        let c = client
        netQueue.async { msgs.forEach { c?.publish(topic: $0.0, payload: $0.1, qos: $0.2, retain: $0.3) } }
    }

    private func scheduleReconnect() {
        guard !isStopped, settings.isConfigured else { return }
        reconnectAttempt += 1
        let delay = reconnectDelay
        reconnectDelay = min(reconnectDelay * 2, 60)
        logger.notice("Reconnecting in \(delay)s (attempt \(self.reconnectAttempt))")

        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in self?.connect(reason: "retry") }
        }
        reconnectItem = item
        netQueue.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func cancelReconnect() {
        reconnectItem?.cancel()
        reconnectItem = nil
    }
}

// ===========================================================================
// MARK: - MQTTRawClient (runs on background queue)
// ===========================================================================

private final class MQTTRawClient {
    struct Config {
        let host:        String
        let port:        UInt16
        let useTLS:      Bool
        let clientID:    String
        let username:    String?
        let password:    String?
        let keepAlive:   UInt16
        let willTopic:   String
        let willPayload: String
        let willQoS:     UInt8
        let willRetain:  Bool
    }

    var onConnected:    (() -> Void)?
    var onDisconnected: ((_ expected: Bool, _ error: String?) -> Void)?
    var onMessage:      ((_ topic: String, _ payload: String) -> Void)?

    private let config:  Config
    private let queue:   DispatchQueue
    private let logger   = Logger(subsystem: "com.jchadwick.musicpauser", category: "MQTTRawClient")

    private var conn:          NWConnection?
    private var buffer         = Data()
    private var pingTimer:     DispatchSourceTimer?
    private var packetCounter: UInt16 = 0
    private var didReportDisconnect = false
    private var disconnectExpected  = false

    init(config: Config, queue: DispatchQueue) {
        self.config = config
        self.queue  = queue
    }

    // MARK: Lifecycle

    func start() {
        queue.async { [weak self] in self?.startOnQueue() }
    }

    func disconnect(sendOffline: Bool) {
        queue.async { [weak self] in
            guard let self else { return }
            self.disconnectExpected = true
            self.stopPing()
            if sendOffline {
                let offlinePacket = MQTTPacketBuilder.publish(
                    topic: self.config.willTopic, payload: self.config.willPayload,
                    qos: self.config.willQoS, retain: self.config.willRetain, packetID: nil)
                self.send(offlinePacket) { [weak self] in
                    self?.conn?.send(content: MQTTPacketBuilder.disconnect(), completion: .idempotent)
                    self?.conn?.cancel()
                }
            } else {
                self.conn?.cancel()
            }
        }
    }

    func publish(topic: String, payload: String, qos: UInt8, retain: Bool) {
        let pid: UInt16? = qos > 0 ? nextPID() : nil
        let pkt = MQTTPacketBuilder.publish(topic: topic, payload: payload, qos: qos, retain: retain, packetID: pid)
        send(pkt, completion: nil)
    }

    func subscribe(topic: String, qos: UInt8) {
        let pkt = MQTTPacketBuilder.subscribe(topic: topic, qos: qos, packetID: nextPID())
        send(pkt, completion: nil)
    }

    // MARK: Private

    private func startOnQueue() {
        let params: NWParameters = config.useTLS ? .tls : .tcp
        guard let nwPort = NWEndpoint.Port(rawValue: config.port) else {
            reportDisconnected(expected: false, error: "Invalid port \(config.port)")
            return
        }
        let c = NWConnection(host: .init(config.host), port: nwPort, using: params)
        conn = c

        c.stateUpdateHandler = { [weak self] state in
            self?.queue.async { self?.handleState(state) }
        }
        c.start(queue: queue)
        receiveLoop(on: c)
    }

    private func handleState(_ state: NWConnection.State) {
        switch state {
        case .ready:
            sendConnect()
        case .failed(let e):
            conn?.cancel(); conn = nil
            reportDisconnected(expected: false, error: "TCP failed: \(e.localizedDescription)")
        case .cancelled:
            conn = nil
            reportDisconnected(expected: disconnectExpected, error: nil)
        case .waiting(let e):
            conn?.cancel(); conn = nil
            reportDisconnected(expected: false, error: "TCP waiting: \(e.localizedDescription)")
        default:
            break
        }
    }

    private func sendConnect() {
        let pkt = MQTTPacketBuilder.connect(
            clientID:    config.clientID,
            username:    config.username,
            password:    config.password,
            keepAlive:   config.keepAlive,
            willTopic:   config.willTopic,
            willPayload: config.willPayload,
            willQoS:     config.willQoS,
            willRetain:  config.willRetain
        )
        send(pkt, completion: nil)
    }

    private func receiveLoop(on c: NWConnection) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isDone, error in
            guard let self else { return }
            self.queue.async {
                if let d = data, !d.isEmpty {
                    self.buffer.append(d)
                    self.parseBuffer()
                }
                if let e = error {
                    self.conn?.cancel(); self.conn = nil
                    self.reportDisconnected(expected: false, error: "Receive: \(e.localizedDescription)")
                    return
                }
                if isDone {
                    self.conn = nil
                    self.reportDisconnected(expected: false, error: "Connection closed by broker")
                    return
                }
                self.receiveLoop(on: c)
            }
        }
    }

    // MARK: Buffer parsing

    private func parseBuffer() {
        while true {
            guard let hdr = decodeHeader(buffer) else { break }
            guard buffer.count >= hdr.totalLength else { break }
            let pkt = buffer.prefix(hdr.totalLength)
            buffer.removeFirst(hdr.totalLength)
            dispatchPacket(type: hdr.type, flags: hdr.flags, body: pkt.dropFirst(hdr.headerLen))
        }
    }

    private struct FixedHeader {
        let type: UInt8; let flags: UInt8; let headerLen: Int; let totalLength: Int
    }

    private func decodeHeader(_ data: Data) -> FixedHeader? {
        guard data.count >= 2 else { return nil }
        let first = data[data.startIndex]
        var mul = 1; var rem = 0; var i = 1
        while true {
            guard i < data.count else { return nil }
            let b = Int(data[data.startIndex + i]); rem += (b & 0x7F) * mul; mul <<= 7; i += 1
            if b & 0x80 == 0 { break }
            if i > 5 { return nil }
        }
        return FixedHeader(type: first >> 4, flags: first & 0x0F, headerLen: i, totalLength: i + rem)
    }

    private func dispatchPacket(type: UInt8, flags: UInt8, body: Data.SubSequence) {
        switch type {
        case 2: handleConnack(body)
        case 3: handlePublish(flags: flags, body: body)
        case 4: break  // PUBACK — no-op for minimal client
        case 9: break  // SUBACK — no-op
        case 13: logger.debug("PINGRESP")
        default: logger.warning("Unknown packet type \(type)")
        }
    }

    private func handleConnack(_ body: Data.SubSequence) {
        guard body.count >= 2 else { return }
        let rc = body[body.startIndex + 1]
        if rc == 0 {
            startPing()
            onConnected?()
        } else {
            conn?.cancel(); conn = nil
            reportDisconnected(expected: false, error: "CONNACK refused (code \(rc))")
        }
    }

    private func handlePublish(flags: UInt8, body: Data.SubSequence) {
        let qos = (flags >> 1) & 0x03
        var idx = body.startIndex
        guard idx + 2 <= body.endIndex else { return }
        let tLen = Int(body[idx]) << 8 | Int(body[idx + 1]); idx += 2
        guard idx + tLen <= body.endIndex else { return }
        let topic = String(data: body[idx..<(idx + tLen)], encoding: .utf8) ?? ""; idx += tLen
        if qos > 0 {
            guard idx + 2 <= body.endIndex else { return }
            let pid = UInt16(body[idx]) << 8 | UInt16(body[idx + 1]); idx += 2
            send(MQTTPacketBuilder.puback(packetID: pid), completion: nil)
        }
        let payload = String(data: body[idx...], encoding: .utf8) ?? ""
        onMessage?(topic, payload)
    }

    // MARK: Ping

    private func startPing() {
        stopPing()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 30, repeating: 30)
        t.setEventHandler { [weak self] in self?.send(MQTTPacketBuilder.pingreq(), completion: nil) }
        t.resume()
        pingTimer = t
    }

    private func stopPing() { pingTimer?.cancel(); pingTimer = nil }

    // MARK: Low-level send

    private func send(_ data: Data, completion: (() -> Void)?) {
        conn?.send(content: data, completion: .contentProcessed { [weak self] error in
            if let error { self?.logger.error("Send error: \(error)") }
            completion?()
        })
    }

    private func nextPID() -> UInt16 {
        packetCounter = (packetCounter == UInt16.max) ? 1 : packetCounter + 1
        return packetCounter
    }

    private func reportDisconnected(expected: Bool, error: String?) {
        guard !didReportDisconnect else { return }
        didReportDisconnect = true
        stopPing()
        onDisconnected?(expected, error)
    }
}

// ===========================================================================
// MARK: - MQTT 3.1.1 Packet Builder
// ===========================================================================

private enum MQTTPacketBuilder {

    // MARK: CONNECT

    static func connect(
        clientID: String, username: String?, password: String?,
        keepAlive: UInt16, willTopic: String, willPayload: String,
        willQoS: UInt8, willRetain: Bool
    ) -> Data {
        var flags: UInt8 = 0b0000_0010  // clean session
        flags |= 0b0000_0100            // will flag
        flags |= (willQoS & 0b11) << 3
        if willRetain  { flags |= 0b0010_0000 }
        if username != nil { flags |= 0b1000_0000 }
        if password != nil { flags |= 0b0100_0000 }

        var varHeader = Data()
        varHeader.append(mqttStr("MQTT"))
        varHeader.append(0x04)  // protocol level 3.1.1
        varHeader.append(flags)
        varHeader.append(UInt8(keepAlive >> 8))
        varHeader.append(UInt8(keepAlive & 0xFF))

        var payload = Data()
        payload.append(mqttStr(clientID))
        payload.append(mqttStr(willTopic))
        payload.append(mqttStr(willPayload))
        if let u = username { payload.append(mqttStr(u)) }
        if let p = password { payload.append(mqttStr(p)) }

        return frame(type: 1, flags: 0, body: varHeader + payload)
    }

    // MARK: PUBLISH

    static func publish(topic: String, payload: String, qos: UInt8, retain: Bool, packetID: UInt16?) -> Data {
        let pktFlags: UInt8 = ((qos & 0b11) << 1) | (retain ? 1 : 0)
        var body = Data()
        body.append(mqttStr(topic))
        if qos > 0 {
            let pid = packetID ?? 1
            body.append(UInt8(pid >> 8)); body.append(UInt8(pid & 0xFF))
        }
        body.append(payload.data(using: .utf8) ?? Data())
        return frame(type: 3, flags: pktFlags, body: body)
    }

    // MARK: SUBSCRIBE

    static func subscribe(topic: String, qos: UInt8, packetID: UInt16) -> Data {
        var body = Data()
        body.append(UInt8(packetID >> 8)); body.append(UInt8(packetID & 0xFF))
        body.append(mqttStr(topic))
        body.append(qos & 0b11)
        return frame(type: 8, flags: 0b0010, body: body)
    }

    // MARK: PINGREQ / DISCONNECT / PUBACK

    static func pingreq()  -> Data { Data([0xC0, 0x00]) }
    static func disconnect() -> Data { Data([0xE0, 0x00]) }
    static func puback(packetID: UInt16) -> Data {
        Data([0x40, 0x02, UInt8(packetID >> 8), UInt8(packetID & 0xFF)])
    }

    // MARK: Helpers

    private static func frame(type: UInt8, flags: UInt8, body: Data) -> Data {
        var out = Data()
        out.append((type << 4) | (flags & 0x0F))
        out.append(encodeLength(body.count))
        out.append(body)
        return out
    }

    private static func encodeLength(_ n: Int) -> Data {
        var x = n; var out = Data()
        repeat {
            var b = UInt8(x & 0x7F); x >>= 7
            if x > 0 { b |= 0x80 }
            out.append(b)
        } while x > 0
        return out
    }

    private static func mqttStr(_ s: String) -> Data {
        let bytes = s.data(using: .utf8) ?? Data()
        var out   = Data()
        out.append(UInt8(bytes.count >> 8)); out.append(UInt8(bytes.count & 0xFF))
        out.append(bytes)
        return out
    }
}
