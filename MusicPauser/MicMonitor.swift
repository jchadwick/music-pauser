import CoreAudio
import Foundation
import os

/// Monitors ALL audio input devices (including virtual ones like ZoomAudioDevice)
/// and reports whether ANY of them is currently in use by any process.
final class MicMonitor {

    // MARK: - Public

    /// Called on the main queue whenever the aggregate in-use state changes.
    var onChange: ((Bool) -> Void)?

    // MARK: - Private

    private let logger = Logger(subsystem: "com.jchadwick.musicpauser", category: "MicMonitor")
    private let listenerQueue = DispatchQueue(label: "com.jchadwick.musicpauser.coreaudio", qos: .userInteractive)
    private let lock = NSLock()

    // deviceID → retained listener block for that device
    private var deviceListenerBlocks: [AudioDeviceID: AudioObjectPropertyListenerBlock] = [:]

    // Per-device running state; any true → overall inUse = true
    private var deviceRunningState: [AudioDeviceID: Bool] = [:]

    private var lastReportedInUse: Bool?
    private var isStarted = false

    // Listener block for kAudioHardwarePropertyDevices (device list changes)
    private var deviceListListenerBlock: AudioObjectPropertyListenerBlock?

    // MARK: - Start / Stop

    func start() {
        lock.lock()
        if isStarted { lock.unlock(); return }
        isStarted = true
        lock.unlock()

        logger.notice("MicMonitor.start()")

        // Watch for devices being added or removed.
        installDeviceListListener()

        // Attach listeners to all current input devices.
        let inputDevices = allInputDeviceIDs()
        logger.notice("Found \(inputDevices.count) input device(s) at launch: \(inputDevices)")
        for id in inputDevices {
            attachListener(to: id)
        }

        // Report initial aggregate state.
        reportAggregate(reason: "initial state at launch")
    }

    func stop() {
        lock.lock()
        if !isStarted { lock.unlock(); return }
        isStarted = false
        let devicesToClean = Array(deviceListenerBlocks.keys)
        lock.unlock()

        logger.notice("MicMonitor.stop()")
        removeDeviceListListener()
        for id in devicesToClean {
            detachListener(from: id)
        }
    }

    // MARK: - Device list listener (handles Zoom adding/removing its virtual device)

    private func installDeviceListListener() {
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.handleDeviceListChanged()
        }
        deviceListListenerBlock = block
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope:    kAudioObjectPropertyScopeGlobal,
            mElement:  kAudioObjectPropertyElementMain
        )
        let err = AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, listenerQueue, block)
        if err != noErr {
            logger.error("Failed to install device-list listener: \(err)")
        } else {
            logger.notice("Device-list listener installed")
        }
    }

    private func removeDeviceListListener() {
        guard let block = deviceListListenerBlock else { return }
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope:    kAudioObjectPropertyScopeGlobal,
            mElement:  kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, listenerQueue, block)
        deviceListListenerBlock = nil
    }

    private func handleDeviceListChanged() {
        let currentInputDevices = Set(allInputDeviceIDs())
        let monitoredDevices: Set<AudioDeviceID> = lock.withLock { Set(deviceListenerBlocks.keys) }

        let added   = currentInputDevices.subtracting(monitoredDevices)
        let removed = monitoredDevices.subtracting(currentInputDevices)

        if !added.isEmpty {
            logger.notice("New input device(s) appeared: \(added) — attaching listeners")
            for id in added { attachListener(to: id) }
        }
        if !removed.isEmpty {
            logger.notice("Input device(s) disappeared: \(removed) — removing listeners")
            for id in removed { detachListener(from: id) }
        }
        if !added.isEmpty || !removed.isEmpty {
            reportAggregate(reason: "device list changed")
        }
    }

    // MARK: - Per-device listener

    private func attachListener(to deviceID: AudioDeviceID) {
        let name = deviceName(deviceID)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self else { return }
            self.handleDeviceRunningStateChanged(deviceID: deviceID)
        }
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope:    kAudioObjectPropertyScopeGlobal,
            mElement:  kAudioObjectPropertyElementMain
        )
        let err = AudioObjectAddPropertyListenerBlock(deviceID, &addr, listenerQueue, block)
        if err != noErr {
            logger.error("Failed to attach listener to device \(deviceID) '\(name)': \(err)")
            return
        }

        // Read initial state for this device.
        let inUse = readIsRunningSomewhere(deviceID)
        lock.lock()
        deviceListenerBlocks[deviceID] = block
        deviceRunningState[deviceID] = inUse
        lock.unlock()

        logger.notice("Listener attached to device \(deviceID) '\(name)' — initial isRunningSomewhere=\(inUse)")
    }

    private func detachListener(from deviceID: AudioDeviceID) {
        lock.lock()
        guard let block = deviceListenerBlocks[deviceID] else { lock.unlock(); return }
        deviceListenerBlocks.removeValue(forKey: deviceID)
        deviceRunningState.removeValue(forKey: deviceID)
        lock.unlock()

        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope:    kAudioObjectPropertyScopeGlobal,
            mElement:  kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(deviceID, &addr, listenerQueue, block)
        let name = deviceName(deviceID)
        logger.notice("Listener detached from device \(deviceID) '\(name)'")
    }

    private func handleDeviceRunningStateChanged(deviceID: AudioDeviceID) {
        let inUse = readIsRunningSomewhere(deviceID)
        let name = deviceName(deviceID)
        logger.notice("Device \(deviceID) '\(name)' isRunningSomewhere changed → \(inUse)")

        lock.lock()
        deviceRunningState[deviceID] = inUse
        lock.unlock()

        reportAggregate(reason: "device \(deviceID) '\(name)' changed to \(inUse)")
    }

    // MARK: - Aggregate reporting

    private func reportAggregate(reason: String) {
        let states: [AudioDeviceID: Bool] = lock.withLock { deviceRunningState }
        let anyInUse = states.values.contains(true)

        // Log per-device breakdown so we can see exactly which device is active.
        for (id, inUse) in states.sorted(by: { $0.key < $1.key }) {
            let name = self.deviceName(id)
            logger.notice("  device \(id) '\(name)': inUse=\(inUse)")
        }
        logger.notice("reportAggregate(\(reason)): anyInUse=\(anyInUse)")

        var shouldNotify = false
        lock.lock()
        if lastReportedInUse != anyInUse {
            lastReportedInUse = anyInUse
            shouldNotify = true
        }
        lock.unlock()

        if shouldNotify {
            logger.notice("Aggregate mic in-use CHANGED → \(anyInUse) — notifying AppState")
            DispatchQueue.main.async { [weak self] in
                self?.onChange?(anyInUse)
            }
        } else {
            logger.notice("Aggregate mic in-use unchanged (\(anyInUse)) — no notification")
        }
    }

    // MARK: - CoreAudio helpers

    private func allInputDeviceIDs() -> [AudioDeviceID] {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope:    kAudioObjectPropertyScopeGlobal,
            mElement:  kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &dataSize) == noErr else { return [] }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &dataSize, &deviceIDs) == noErr else { return [] }

        return deviceIDs.filter { hasInputStreams($0) }
    }

    private func hasInputStreams(_ deviceID: AudioDeviceID) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope:    kAudioDevicePropertyScopeInput,
            mElement:  kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(deviceID, &addr, 0, nil, &size) == noErr && size > 0
    }

    private func readIsRunningSomewhere(_ deviceID: AudioDeviceID) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope:    kAudioObjectPropertyScopeGlobal,
            mElement:  kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let err = AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &value)
        if err != noErr {
            logger.error("readIsRunningSomewhere(\(deviceID)): error \(err)")
            return false
        }
        return value != 0
    }

    private func deviceName(_ deviceID: AudioDeviceID) -> String {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope:    kAudioObjectPropertyScopeGlobal,
            mElement:  kAudioObjectPropertyElementMain
        )
        var name: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &name)
        return name as String
    }
}
