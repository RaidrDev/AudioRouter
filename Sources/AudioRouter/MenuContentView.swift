import SwiftUI

struct MenuContentView: View {
    @EnvironmentObject var processStore: AudioProcessStore
    @EnvironmentObject var routing: RoutingManager
    @EnvironmentObject var systemAudio: SystemAudioController
    @EnvironmentObject var updater: UpdaterController

    @State private var isSystemExpanded = true

    private var devices: [OutputDevice] { OutputDevice.listAll() }

    private var audioProcesses: [AudioProcess] {
        processStore.processes.filter { $0.kind == .app && ($0.isRunningAudio || routing.activeRoutes[$0.id] != nil) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider().opacity(0.5)

            systemSection

            Divider().opacity(0.5)

            if let error = routing.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(10)
                Divider().opacity(0.5)
            }

            if audioProcesses.isEmpty {
                Text("No app is playing audio right now.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            } else {
                VStack(spacing: 2) {
                    ForEach(audioProcesses) { process in
                        AppRow(process: process, devices: devices)
                    }
                }
                .padding(.vertical, 6)
            }

            Divider().opacity(0.5)

            footer
        }
        .frame(width: 460)
        .background(VisualEffectView())
        .onAppear {
            processStore.refresh()
            routing.pruneRouters(activeIDs: Set(processStore.processes.map(\.id)))
            routing.reapplySavedAssignments(processes: processStore.processes, availableDevices: devices)
        }
    }

    private var systemSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { isSystemExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .rotationEffect(.degrees(isSystemExpanded ? 0 : -90))
                    Text("System")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isSystemExpanded {
                VStack(spacing: 10) {
                    SystemVolumeRow(
                        symbolName: "speaker.wave.3.fill",
                        value: Binding(get: { systemAudio.outputVolume }, set: { systemAudio.setOutputVolume($0) }),
                        trailing: {
                            AnyView(
                                DevicePicker(
                                    devices: devices,
                                    includeSystemDefaultOption: false,
                                    selectedUID: Binding(
                                        get: { systemAudio.outputDevice?.uid },
                                        set: { uid in
                                            if let uid, let device = devices.first(where: { $0.uid == uid }) {
                                                systemAudio.setOutputDevice(device)
                                            }
                                        }
                                    )
                                )
                            )
                        }
                    )
                    SystemVolumeRow(
                        symbolName: "bolt.fill",
                        value: Binding(get: { systemAudio.alertVolume }, set: { systemAudio.setAlertVolume($0) })
                    )
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
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

private struct AppRow: View {
    let process: AudioProcess
    let devices: [OutputDevice]

    @EnvironmentObject var routing: RoutingManager
    @State private var isHovering = false

    private var currentDevice: OutputDevice? { routing.activeRoutes[process.id] }
    private var gainBinding: Binding<Float> {
        Binding(
            get: { routing.gains[process.id] ?? 1.0 },
            set: { routing.setGain($0, for: process.id) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                Image(nsImage: process.icon)
                    .resizable()
                    .frame(width: 26, height: 26)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                Text(process.name)
                    .font(.system(size: 13))
                    .lineLimit(1)

                Spacer(minLength: 8)
            }

            HStack(spacing: 8) {
                deviceMenu

                LevelMeterView(level: routing.levels[process.id] ?? 0)

                FlatSlider(value: gainBinding)
                    .disabled(currentDevice == nil)
                    .opacity(currentDevice == nil ? 0.35 : 1)
            }
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
    @Binding var value: Float
    var trailing: (() -> AnyView)?

    init(symbolName: String, value: Binding<Float>, trailing: (() -> AnyView)? = nil) {
        self.symbolName = symbolName
        self._value = value
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbolName)
                .font(.system(size: 12))
                .frame(width: 16)
                .foregroundStyle(.secondary)

            FlatSlider(value: $value, range: 0...1)

            Text("\(Int(value * 100))%")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 32, alignment: .trailing)

            if let trailing {
                trailing()
            }
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
