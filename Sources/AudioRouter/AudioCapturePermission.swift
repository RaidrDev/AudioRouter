import Foundation
import OSLog

private let permissionLog = Logger(subsystem: "dev.raidr.audiorouter", category: "Permission")

/// Triggers the native "Screen & System Audio Recording" permission dialog on first launch.
///
/// There is no public API for this yet (as of macOS 15), only the private one TCC itself
/// uses internally. Since this app isn't sandboxed / App Store-distributed, calling it
/// directly is the only way to avoid asking the user to add the app manually every time.
/// If Apple removes or renames this symbol in a future release, `requestIfNeeded` just
/// becomes a no-op and the user falls back to adding the app by hand in System Settings.
enum AudioCapturePermission {
    enum Status {
        case authorized
        case denied
        case unknown
    }

    private typealias PreflightFn = @convention(c) (CFString, CFDictionary?) -> Int
    private typealias RequestFn = @convention(c) (CFString, CFDictionary?, @escaping (Bool) -> Void) -> Void

    nonisolated(unsafe) private static let tccHandle: UnsafeMutableRawPointer? = {
        dlopen("/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC", RTLD_NOW)
    }()

    private static let preflight: PreflightFn? = {
        guard let tccHandle, let sym = dlsym(tccHandle, "TCCAccessPreflight") else { return nil }
        return unsafeBitCast(sym, to: PreflightFn.self)
    }()

    private static let request: RequestFn? = {
        guard let tccHandle, let sym = dlsym(tccHandle, "TCCAccessRequest") else { return nil }
        return unsafeBitCast(sym, to: RequestFn.self)
    }()

    static func currentStatus() -> Status {
        guard let preflight else { return .unknown }
        switch preflight("kTCCServiceAudioCapture" as CFString, nil) {
        case 0: return .authorized
        case 1: return .denied
        default: return .unknown
        }
    }

    /// Shows the system permission dialog if the user hasn't been asked yet.
    /// Does nothing if already authorized/denied, or if the SPI isn't available.
    static func requestIfNeeded() {
        let status = currentStatus()
        permissionLog.notice("audio capture permission status at launch: \(String(describing: status), privacy: .public)")

        guard status != .authorized else { return }
        guard let request else {
            permissionLog.error("TCCAccessRequest unavailable, cannot prompt automatically")
            return
        }

        request("kTCCServiceAudioCapture" as CFString, nil) { granted in
            permissionLog.notice("audio capture permission request result: \(granted, privacy: .public)")
        }
    }
}
