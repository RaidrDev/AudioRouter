import AppKit
import AudioToolbox
import Combine

struct AudioProcess: Identifiable, Hashable {
    /// `app`: a real, user-facing application (or one/more helper/renderer subprocesses we
    /// traced back to a parent .app, e.g. a Chromium GPU/audio helper).
    /// `system`: a background daemon/XPC service with no owning .app bundle
    /// (e.g. com.apple.audio.SystemSoundServer-xpc) — not useful to route per-app.
    enum Kind { case app, system }

    /// Stable grouping key: bundle ID when available, else the bundle path, else "pid:<n>".
    let id: String
    /// All Core Audio process objects that belong to this app (a browser may have several
    /// helper processes producing audio at once; they're tapped together as one unit).
    let objectIDs: [AudioObjectID]
    let pids: [pid_t]
    let name: String
    let bundleID: String?
    let bundleURL: URL?
    let isRunningAudio: Bool
    let kind: Kind

    var icon: NSImage {
        guard let bundleURL else { return NSWorkspace.shared.icon(for: .unixExecutable) }
        return NSWorkspace.shared.icon(forFile: bundleURL.path)
    }
}

@MainActor
final class AudioProcessStore: ObservableObject {
    @Published private(set) var processes: [AudioProcess] = []

    private var cancellables = Set<AnyCancellable>()
    private var refreshTimer: Timer?

    func start() {
        NSWorkspace.shared
            .publisher(for: \.runningApplications, options: [.initial, .new])
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)

        // Audio activity (song starts/stops) doesn't emit a workspace notification, so poll lightly too.
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        guard let objectIDs = try? SystemAudioObject.processObjectList() else { return }
        let runningApps = NSWorkspace.shared.runningApplications
        let myPID = ProcessInfo.processInfo.processIdentifier

        struct Entry {
            var objectIDs: [AudioObjectID] = []
            var pids: [pid_t] = []
            var name = ""
            var bundleID: String?
            var bundleURL: URL?
            var isRunningAudio = false
            var kind: AudioProcess.Kind = .system
        }

        var entriesByKey: [String: Entry] = [:]

        for objectID in objectIDs {
            guard let pid = objectID.readPID(kAudioProcessPropertyPID), pid != myPID, pid > 0 else { continue }
            let isRunningAudio = objectID.readBool(kAudioProcessPropertyIsRunningOutput)
            let rawBundleID = objectID.readString(kAudioProcessPropertyBundleID)

            var key: String
            var name: String
            var bundleID: String?
            var bundleURL: URL?
            var kind: AudioProcess.Kind

            if let app = runningApps.first(where: { $0.processIdentifier == pid }) {
                key = app.bundleIdentifier ?? "pid:\(pid)"
                name = app.localizedName ?? rawBundleID ?? "PID \(pid)"
                bundleID = app.bundleIdentifier
                bundleURL = app.bundleURL
                kind = .app
            } else if let appURL = Self.outermostAppBundle(forPID: pid) {
                // Helper/renderer subprocess (browsers spawn one per tab/audio service): fold
                // it into the same entry as its owning app instead of showing it separately.
                let bundle = Bundle(url: appURL)
                key = bundle?.bundleIdentifier ?? appURL.path
                name = (bundle?.infoDictionary?["CFBundleName"] as? String) ?? appURL.deletingPathExtension().lastPathComponent
                bundleID = bundle?.bundleIdentifier
                bundleURL = appURL
                kind = .app
            } else {
                let rawName = Self.processName(forPID: pid) ?? rawBundleID ?? "PID \(pid)"
                // Apple's own auxiliary processes (e.g. "Safari Graphics", "Safari Web
                // Content") aren't nested inside the parent .app bundle like Chromium
                // helpers are — they're separate XPC services — so match them to their
                // owning app by name prefix instead.
                if let owner = runningApps.first(where: { app in
                    guard let appName = app.localizedName, !appName.isEmpty else { return false }
                    return rawName.hasPrefix(appName + " ")
                }) {
                    key = owner.bundleIdentifier ?? "pid:\(pid)"
                    name = owner.localizedName ?? rawName
                    bundleID = owner.bundleIdentifier
                    bundleURL = owner.bundleURL
                    kind = .app
                } else {
                    key = "pid:\(pid)"
                    name = rawName
                    bundleID = rawBundleID
                    bundleURL = nil
                    kind = .system
                }
            }

            var entry = entriesByKey[key] ?? Entry()
            entry.objectIDs.append(objectID)
            entry.pids.append(pid)
            entry.name = name
            entry.bundleID = bundleID
            entry.bundleURL = bundleURL
            entry.kind = kind
            entry.isRunningAudio = entry.isRunningAudio || isRunningAudio
            entriesByKey[key] = entry
        }

        let updated: [AudioProcess] = entriesByKey.map { key, entry in
            AudioProcess(
                id: key,
                objectIDs: entry.objectIDs,
                pids: entry.pids,
                name: entry.name,
                bundleID: entry.bundleID,
                bundleURL: entry.bundleURL,
                isRunningAudio: entry.isRunningAudio,
                kind: entry.kind
            )
        }
        .sorted { lhs, rhs in
            if lhs.isRunningAudio != rhs.isRunningAudio { return lhs.isRunningAudio }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        if updated != processes { processes = updated }
    }

    private static func processName(forPID pid: pid_t) -> String? {
        var buffer = [UInt8](repeating: 0, count: Int(MAXPATHLEN))
        let length = proc_name(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)), as: UTF8.self)
    }

    /// Climbs from the process's executable up to the outermost `.app` bundle it lives
    /// inside. Helper/renderer executables sit several levels deep
    /// (`Brave Browser.app/Contents/Frameworks/.../Helpers/Brave Browser Helper (Renderer).app/...`),
    /// so we keep climbing past the first `.app` we find and return the last (outermost) one.
    private static func outermostAppBundle(forPID pid: pid_t) -> URL? {
        var buffer = [UInt8](repeating: 0, count: Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        let executableURL = URL(fileURLWithPath: String(decoding: buffer.prefix(Int(length)), as: UTF8.self))

        var outermost: URL?
        var url = executableURL.deletingLastPathComponent()
        for _ in 0..<12 {
            if url.pathExtension == "app" { outermost = url }
            let parent = url.deletingLastPathComponent()
            if parent == url { break }
            url = parent
        }
        return outermost
    }
}
