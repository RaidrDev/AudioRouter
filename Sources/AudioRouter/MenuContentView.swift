import SwiftUI

struct MenuContentView: View {
    @EnvironmentObject var processStore: AudioProcessStore
    @EnvironmentObject var routing: RoutingManager
    @EnvironmentObject var systemAudio: SystemAudioController
    @EnvironmentObject var updater: UpdaterController

    private var devices: [OutputDevice] { OutputDevice.listAll() }

    private var audioProcesses: [AudioProcess] {
        processStore.processes.filter { $0.kind == .app && ($0.isRunningAudio || routing.activeRoutes[$0.id] != nil) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider().opacity(0.5)

            outputDevicesSection

            Divider().opacity(0.5)

            if let error = routing.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(10)
                Divider().opacity(0.5)
            }

            sectionLabel("APPS")

            if audioProcesses.isEmpty {
                Text("No app is playing audio right now.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
            } else {
                VStack(spacing: 2) {
                    ForEach(audioProcesses) { process in
                        AppRow(process: process, devices: devices)
                    }
                }
                .padding(.bottom, 6)
            }

            Divider().opacity(0.5)

            footer
        }
        .frame(width: 460)
        .background(VisualEffectView())
        .onAppear {
            processStore.refresh()
            systemAudio.refresh()
            routing.pruneRouters(activeIDs: Set(processStore.processes.map(\.id)))
            routing.reapplySavedAssignments(processes: processStore.processes, availableDevices: devices)
        }
    }

    private func sectionLabel(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .bold))
            .tracking(0.6)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }

    private var outputDevicesSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            sectionLabel("OUTPUT DEVICES")

            ForEach(devices) { device in
                OutputDeviceRow(device: device)
            }

            Divider().opacity(0.4).padding(.vertical, 6).padding(.horizontal, 14)

            SystemVolumeRow(symbolName: "bolt.fill", label: "Sound Effects", value: Binding(
                get: { systemAudio.alertVolume },
                set: { systemAudio.setAlertVolume($0) }
            ))
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
        }
        .padding(.top, 4)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "hifispeaker.fill")
                .foregroundStyle(.secondary)
            Text("AudioRouter")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            HoverIconButton(systemName: "gearshape.fill", help: "Privacy Settings") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
            }

            HoverIconButton(systemName: "arrow.down.circle", help: "Check for Updates…") {
                updater.checkForUpdates()
            }
            .disabled(!updater.canCheckForUpdates)
            .opacity(updater.canCheckForUpdates ? 1 : 0.4)

            Spacer()

            HoverIconButton(systemName: "power", help: "Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .foregroundStyle(.secondary)
        .font(.system(size: 13))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

private struct HoverIconButton: View {
    let systemName: String
    let help: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .frame(width: 26, height: 26)
                .background(isHovering ? Color.white.opacity(0.12) : .clear)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { isHovering = $0 }
    }
}

/// One row per connected output device: tap the leading circle to make it the
/// system default, adjust its own volume/mute independently of whether it's the
/// active device right now (Core Audio exposes both regardless of activity).
private struct OutputDeviceRow: View {
    let device: OutputDevice

    @EnvironmentObject var systemAudio: SystemAudioController
    @State private var isHovering = false

    private var isDefault: Bool { systemAudio.defaultDeviceUID == device.uid }
    private var isMuted: Bool { systemAudio.deviceMutes[device.uid] ?? false }
    private var volumeBinding: Binding<Float> {
        Binding(
            get: { systemAudio.deviceVolumes[device.uid] ?? 1 },
            set: { systemAudio.setVolume($0, for: device) }
        )
    }

    var body: some View {
        HStack(spacing: 9) {
            Button {
                systemAudio.setDefaultDevice(device)
            } label: {
                Image(systemName: isDefault ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13))
                    .foregroundStyle(isDefault ? Color.accentColor : Color.secondary.opacity(0.5))
            }
            .buttonStyle(.plain)

            Image(systemName: device.symbolName)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 15)

            Text(device.name)
                .font(.system(size: 12.5))
                .lineLimit(1)
                .frame(maxWidth: 130, alignment: .leading)

            Spacer(minLength: 6)

            Button {
                systemAudio.toggleMute(for: device)
            } label: {
                Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 10.5))
                    .foregroundStyle(isMuted ? Color.red : Color.secondary)
                    .frame(width: 16)
            }
            .buttonStyle(.plain)

            FlatSlider(value: volumeBinding, range: 0...1)
                .disabled(isMuted)
                .opacity(isMuted ? 0.35 : 1)

            Text("\(Int(volumeBinding.wrappedValue * 100))%")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 32, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .background(isHovering ? Color.white.opacity(0.05) : .clear)
        .onHover { isHovering = $0 }
    }
}

private struct AppRow: View {
    let process: AudioProcess
    let devices: [OutputDevice]

    @EnvironmentObject var routing: RoutingManager
    @State private var isHovering = false

    private var currentDevice: OutputDevice? { routing.activeRoutes[process.id] }
    private var isMuted: Bool { (routing.gains[process.id] ?? 1) <= 0 }
    private var gainBinding: Binding<Float> {
        Binding(
            get: { routing.gains[process.id] ?? 1.0 },
            set: { routing.setGain($0, for: process.id) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(nsImage: process.icon)
                    .resizable()
                    .frame(width: 24, height: 24)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                Text(process.name)
                    .font(.system(size: 13))
                    .lineLimit(1)

                Spacer(minLength: 8)

                deviceMenu
            }

            HStack(spacing: 8) {
                Button {
                    routing.toggleMute(for: process.id)
                } label: {
                    Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 10.5))
                        .foregroundStyle(isMuted ? Color.red : Color.secondary)
                        .frame(width: 16)
                }
                .buttonStyle(.plain)
                .disabled(currentDevice == nil)

                FlatSlider(value: gainBinding)
                    .disabled(currentDevice == nil)

                Text("\(Int(gainBinding.wrappedValue * 100))%")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 34, alignment: .trailing)

                LevelMeterView(level: routing.levels[process.id] ?? 0)
            }
            .opacity(currentDevice == nil ? 0.35 : 1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(isHovering ? Color.white.opacity(0.06) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.horizontal, 6)
        .onHover { isHovering = $0 }
    }

    private var deviceMenu: some View {
        DevicePicker(
            devices: devices,
            includeSystemDefaultOption: true,
            selectedUID: Binding(
                get: { currentDevice?.uid },
                set: { uid in
                    if let uid, let device = devices.first(where: { $0.uid == uid }) {
                        routing.route(process: process, to: device)
                    } else {
                        routing.resetToDefault(process: process)
                    }
                }
            )
        )
    }
}

/// Plain, native macOS pop-up button (`NSPopUpButton` under the hood) — no custom
/// drawing at all, so it renders exactly like every other dropdown in the system.
private struct DevicePicker: View {
    let devices: [OutputDevice]
    let includeSystemDefaultOption: Bool
    @Binding var selectedUID: String?

    var body: some View {
        Picker("", selection: $selectedUID) {
            if includeSystemDefaultOption {
                Text("System Default").tag(String?.none)
            }
            ForEach(devices) { device in
                Text(device.name).tag(Optional(device.uid))
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .controlSize(.small)
        .fixedSize()
    }
}

private struct SystemVolumeRow: View {
    let symbolName: String
    let label: LocalizedStringKey
    @Binding var value: Float

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbolName)
                .font(.system(size: 12))
                .frame(width: 15)
                .foregroundStyle(.secondary)

            Text(label)
                .font(.system(size: 12.5))
                .lineLimit(1)
                .frame(maxWidth: 130, alignment: .leading)

            Spacer(minLength: 6)

            FlatSlider(value: $value, range: 0...1)

            Text("\(Int(value * 100))%")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 32, alignment: .trailing)
        }
    }
}

/// Classic single-bar VU meter. Only shows real data — fills with the live peak level
/// while the app is routed through our own tap; sits empty otherwise (no invented
/// animation when there's no actual signal to show, e.g. "System Default").
private struct LevelMeterView: View {
    var level: Float

    private let width: CGFloat = 7
    private let height: CGFloat = 14
    private let cornerRadius: CGFloat = 3.5

    var body: some View {
        // sqrt boosts quiet moments instead of only reacting to loud peaks — reads as
        // a much livelier, more sensitive meter.
        let fraction = level > 0.001 ? min(sqrt(CGFloat(level)) * 1.5, 1) : 0

        bar(fraction: fraction)
            .animation(.easeOut(duration: 0.06), value: level)
            .frame(width: width, height: height)
    }

    private func bar(fraction: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.white.opacity(0.12))

            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(fraction > 0.85 ? AnyShapeStyle(Color.red.gradient) : AnyShapeStyle(Color.accentColor.gradient))
                .frame(height: height * fraction)
        }
    }
}
