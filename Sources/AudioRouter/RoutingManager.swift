import Foundation

@MainActor
final class RoutingManager: ObservableObject {
    @Published private(set) var activeRoutes: [String: OutputDevice] = [:]
    @Published private(set) var gains: [String: Float] = [:]
    @Published private(set) var levels: [String: Float] = [:]
    @Published var lastError: String?

    private var routers: [String: ProcessRouter] = [:]
    private var preMuteGains: [String: Float] = [:]
    private var levelTimer: Timer?
    private let defaults = UserDefaults.standard
    private let assignmentsKey = "dev.raidr.audiorouter.assignments"

    private var assignments: [String: String] {
        get { defaults.dictionary(forKey: assignmentsKey) as? [String: String] ?? [:] }
        set { defaults.set(newValue, forKey: assignmentsKey) }
    }

    init() {
        // 20Hz is plenty to look like a live meter without burning CPU on a menu bar extra.
        levelTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollLevels() }
        }
    }

    private func pollLevels() {
        guard !routers.isEmpty else { return }
        for (id, router) in routers {
            levels[id] = router.level
        }
    }

    func savedDeviceUID(for process: AudioProcess) -> String? {
        guard let bundleID = process.bundleID else { return nil }
        return assignments[bundleID]
    }

    func route(process: AudioProcess, to device: OutputDevice) {
        let previousGain = gains[process.id] ?? 1.0
        stopRouting(id: process.id)

        let router = ProcessRouter()
        router.gain = previousGain
        do {
            try router.start(process: process, outputDevice: device)
            routers[process.id] = router
            activeRoutes[process.id] = device
            gains[process.id] = previousGain
            if let bundleID = process.bundleID {
                var a = assignments
                a[bundleID] = device.uid
                assignments = a
            }
            lastError = nil
        } catch {
            let format = String(localized: "Couldn't route %@: %@")
            lastError = String(format: format, process.name, error.localizedDescription)
        }
    }

    func setGain(_ value: Float, for id: String) {
        gains[id] = value
        routers[id]?.gain = value
    }

    func toggleMute(for id: String) {
        let current = gains[id] ?? 1.0
        if current > 0 {
            preMuteGains[id] = current
            setGain(0, for: id)
        } else {
            setGain(preMuteGains[id] ?? 1.0, for: id)
        }
    }

    func stopRouting(id: String) {
        routers[id]?.stop()
        routers[id] = nil
        activeRoutes[id] = nil
        gains[id] = nil
        levels[id] = nil
    }

    func resetToDefault(process: AudioProcess) {
        stopRouting(id: process.id)
        if let bundleID = process.bundleID {
            var a = assignments
            a.removeValue(forKey: bundleID)
            assignments = a
        }
    }

    /// Re-applies a saved per-app assignment when that app starts producing audio again.
    func reapplySavedAssignments(processes: [AudioProcess], availableDevices: [OutputDevice]) {
        for process in processes where process.isRunningAudio && routers[process.id] == nil {
            guard let bundleID = process.bundleID, let savedUID = assignments[bundleID] else { continue }
            guard let device = availableDevices.first(where: { $0.uid == savedUID }) else { continue }
            route(process: process, to: device)
        }
    }

    /// Tears down routers for processes that are no longer running.
    func pruneRouters(activeIDs: Set<String>) {
        for id in routers.keys where !activeIDs.contains(id) {
            stopRouting(id: id)
        }
    }
}
