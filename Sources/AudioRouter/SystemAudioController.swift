import Foundation
import OSLog

private let systemAudioLog = Logger(subsystem: "dev.raidr.audiorouter", category: "SystemAudio")

/// Controls the system-wide output device plus the two volumes it exposes here:
/// output and alert/"sound effects" volume. The alert volume in particular isn't a
/// Core Audio device property — it's only reachable through the same Apple Events
/// "volume settings" command AppleScript and Shortcuts have used for decades, so
/// that's what this uses for both.
@MainActor
final class SystemAudioController: ObservableObject {
    @Published private(set) var outputDevice: OutputDevice?
    @Published var outputVolume: Float = 0.5
    @Published var alertVolume: Float = 0.5

    private var refreshTimer: Timer?

    func start() {
        refresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        outputDevice = OutputDevice.systemDefault()
        if let settings = Self.readVolumeSettings() {
            outputVolume = settings.output
            alertVolume = settings.alert
        }
    }

    func setOutputDevice(_ device: OutputDevice) {
        do {
            try SystemAudioObject.setDefaultOutputDevice(device.objectID)
            outputDevice = device
        } catch {
            systemAudioLog.error("failed to set default output device: \(error, privacy: .public)")
        }
    }

    func setOutputVolume(_ value: Float) {
        outputVolume = value
        Self.run("set volume output volume \(Int(value * 100))")
    }

    func setAlertVolume(_ value: Float) {
        alertVolume = value
        Self.run("set volume alert volume \(Int(value * 100))")
    }

    private static func readVolumeSettings() -> (output: Float, alert: Float)? {
        let source = """
        set s to get volume settings
        return {output volume of s, alert volume of s}
        """
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            systemAudioLog.error("read volume settings failed: \(error, privacy: .public)")
            return nil
        }
        guard result.numberOfItems == 2 else { return nil }
        let output = result.atIndex(1)?.int32Value ?? 50
        let alert = result.atIndex(2)?.int32Value ?? 50
        return (Float(output) / 100, Float(alert) / 100)
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
