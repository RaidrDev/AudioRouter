import ServiceManagement
import OSLog

private let launchAtLoginLog = Logger(subsystem: "dev.raidr.audiorouter", category: "LaunchAtLogin")

/// Registers/unregisters AudioRouter as a login item using the modern
/// ServiceManagement API (macOS 13+) — no separate helper bundle or extra
/// entitlement needed, unlike the old SMLoginItemSetEnabled approach.
@MainActor
final class LaunchAtLoginController: ObservableObject {
    @Published private(set) var isEnabled: Bool = false

    init() {
        refresh()
    }

    func refresh() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    func toggle() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            launchAtLoginLog.error("failed to toggle launch at login: \(error, privacy: .public)")
        }
        refresh()
    }
}
