import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        ProcessRouter.destroyLeakedAggregates()
        AudioCapturePermission.requestIfNeeded()
    }
}

@main
struct AudioRouterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var processStore = AudioProcessStore()
    @StateObject private var routing = RoutingManager()
    @StateObject private var systemAudio = SystemAudioController()
    @StateObject private var updater = UpdaterController()

    var body: some Scene {
        MenuBarExtra("AudioRouter", systemImage: "hifispeaker.fill") {
            MenuContentView()
                .environmentObject(processStore)
                .environmentObject(routing)
                .environmentObject(systemAudio)
                .environmentObject(updater)
                .onAppear {
                    processStore.start()
                    systemAudio.start()
                }
        }
        .menuBarExtraStyle(.window)
    }
}
