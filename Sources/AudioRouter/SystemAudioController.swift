import Foundation
import OSLog

private let systemAudioLog = Logger(subsystem: "dev.raidr.audiorouter", category: "SystemAudio")

/// Controls every connected output device's volume/mute directly via Core Audio
/// (so each one is independently adjustable, not just whichever is currently
/// active), plus the system default device and the alert/"sound effects" volume.
/// The alert volume isn't a Core Audio device property — it's only reachable
/// through the same Apple Events "volume settings" command AppleScript and
/// Shortcuts have used for decades, so that's the one thing here that still uses it.
@MainActor
final class SystemAudioController: ObservableObject {
    @Published private(set) var defaultDeviceUID: String?
    @Published private(set) var deviceVolumes: [String: Float] = [:]
    @Published private(set) var deviceMutes: [String: Bool] = [:]
    @Published var alertVolume: Float = 0.5

    private var refreshTimer: Timer?

    func start() {
        refresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        defaultDeviceUID = OutputDevice.systemDefault()?.uid
        for device in OutputDevice.listAll() {
            if let volume = device.objectID.readOutputVolume() {
                deviceVolumes[device.uid] = volume
            }
            deviceMutes[device.uid] = device.objectID.readOutputMuted()
        }
        if let alert = Self.readAlertVolume() {
            alertVolume = alert
        }
    }

    func setDefaultDevice(_ device: OutputDevice) {
        do {
            try SystemAudioObject.setDefaultOutputDevice(device.objectID)
            defaultDeviceUID = device.uid
        } catch {
            systemAudioLog.error("failed to set default output device: \(error, privacy: .public)")
        }
    }

    func setVolume(_ value: Float, for device: OutputDevice) {
        deviceVolumes[device.uid] = value
        device.objectID.setOutputVolume(value)
    }

    func toggleMute(for device: OutputDevice) {
        let newValue = !(deviceMutes[device.uid] ?? false)
        deviceMutes[device.uid] = newValue
        device.objectID.setOutputMuted(newValue)
    }

    func setAlertVolume(_ value: Float) {
        alertVolume = value
        Self.run("set volume alert volume \(Int(value * 100))")
    }

    private static func readAlertVolume() -> Float? {
        guard let script = NSAppleScript(source: "get alert volume of (get volume settings)") else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            systemAudioLog.error("read alert volume failed: \(error, privacy: .public)")
            return nil
        }
        return Float(result.int32Value) / 100
    }

    private static func run(_ command: String) {
        guard let script = NSAppleScript(source: command) else { return }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        if let error {
            systemAudioLog.error("'\(command, privacy: .public)' failed: \(error, privacy: .public)")
        }
    }
}
