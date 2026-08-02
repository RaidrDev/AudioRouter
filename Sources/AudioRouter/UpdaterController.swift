import Sparkle

/// Thin wrapper around Sparkle's standard updater so SwiftUI can trigger a manual
/// check without reaching into AppKit directly. Automatic background checks and the
/// permission prompt are handled by Sparkle itself using SUFeedURL/SUPublicEDKey
/// from Info.plist.
@MainActor
final class UpdaterController: ObservableObject {
    private let controller = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    @Published private(set) var canCheckForUpdates = false

    init() {
        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
