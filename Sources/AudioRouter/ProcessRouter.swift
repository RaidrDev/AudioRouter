import CoreAudio
import AudioToolbox
import OSLog

private let routerLog = Logger(subsystem: "dev.raidr.audiorouter", category: "ProcessRouter")

/// Captures one process's audio via a Core Audio Process Tap and plays it back
/// on a chosen physical output device (with an adjustable gain), instead of the
/// system default.
final class ProcessRouter {
    /// Destroys any "AudioRouter-*" aggregate devices left behind by a previous run
    /// that was killed instead of quit cleanly (e.g. during development).
    static func destroyLeakedAggregates() {
        guard let deviceIDs = try? SystemAudioObject.allDevices() else { return }
        for deviceID in deviceIDs {
            guard let name = deviceID.readString(kAudioObjectPropertyName), name.hasPrefix("AudioRouter-") else { continue }
            let status = AudioHardwareDestroyAggregateDevice(deviceID)
            routerLog.notice("cleaned up leaked aggregate '\(name, privacy: .public)' (status \(status, privacy: .public))")
        }
    }

    private var tapID = AudioObjectID.unknown
    private var aggregateDeviceID = AudioObjectID.unknown
    private var deviceProcID: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "dev.raidr.audiorouter.ioproc", qos: .userInteractive)

    /// Linear gain (0...1.5-ish) applied to samples as they're copied through. Written from
    /// the main thread by the volume slider, read on the real-time audio thread; a plain Float
    /// read/write is naturally atomic on arm64/x86_64 so this deliberately skips locking —
    /// worst case is a single stale sample, never a torn/garbage value.
    nonisolated(unsafe) var gain: Float32 = 1.0

    /// Peak level of the last-seen buffer (0...1-ish), for the UI's VU meter. Same
    /// relaxed-atomicity reasoning as `gain`: written on the audio thread, read by a
    /// UI polling timer, a stale/torn read is harmless here.
    nonisolated(unsafe) private(set) var level: Float32 = 0

    func start(process: AudioProcess, outputDevice: OutputDevice) throws {
        let tapDescription = CATapDescription(stereoMixdownOfProcesses: process.objectIDs)
        tapDescription.uuid = UUID()
        tapDescription.muteBehavior = .mutedWhenTapped

        var newTapID = AudioObjectID.unknown
        var status = AudioHardwareCreateProcessTap(tapDescription, &newTapID)
        guard status == noErr else { throw CoreAudioError.osStatus("AudioHardwareCreateProcessTap", status) }
        tapID = newTapID

        let aggregateUID = UUID().uuidString
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "AudioRouter-\(process.id)",
            kAudioAggregateDeviceUIDKey: aggregateUID,
            kAudioAggregateDeviceMainSubDeviceKey: outputDevice.uid,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: outputDevice.uid]
            ],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapDriftCompensationKey: true,
                    kAudioSubTapUIDKey: tapDescription.uuid.uuidString
                ]
            ]
        ]

        var newAggregateID = AudioObjectID.unknown
        status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &newAggregateID)
        guard status == noErr else {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = .unknown
            throw CoreAudioError.osStatus("AudioHardwareCreateAggregateDevice", status)
        }
        aggregateDeviceID = newAggregateID

        let ioBlock: AudioDeviceIOBlock = { [weak self] _, inputData, _, outputData, _ in
            let inputBuffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
            let outputBuffers = UnsafeMutableAudioBufferListPointer(outputData)
            let gain = self?.gain ?? 1.0

            for i in 0..<outputBuffers.count {
                guard let outData = outputBuffers[i].mData else { continue }
                let outSize = Int(outputBuffers[i].mDataByteSize)
                guard i < inputBuffers.count, let inData = inputBuffers[i].mData else {
                    memset(outData, 0, outSize)
                    continue
                }

                let copyBytes = min(outSize, Int(inputBuffers[i].mDataByteSize))
                if gain == 1.0 {
                    memcpy(outData, inData, copyBytes)
                } else {
                    let sampleCount = copyBytes / MemoryLayout<Float32>.size
                    let src = inData.assumingMemoryBound(to: Float32.self)
                    let dst = outData.assumingMemoryBound(to: Float32.self)
                    for s in 0..<sampleCount { dst[s] = src[s] * gain }
                }
                if outSize > copyBytes {
                    memset(outData.advanced(by: copyBytes), 0, outSize - copyBytes)
                }
            }

            if let inData = inputBuffers.first?.mData {
                let frameCount = Int(inputBuffers[0].mDataByteSize) / MemoryLayout<Float32>.size
                if frameCount > 0 {
                    let samples = inData.assumingMemoryBound(to: Float32.self)
                    var peak: Float32 = 0
                    for f in stride(from: 0, to: frameCount, by: 4) { peak = max(peak, abs(samples[f])) }
                    self?.level = peak
                }
            }
        }

        var procID: AudioDeviceIOProcID?
        status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateDeviceID, queue, ioBlock)
        guard status == noErr, let procID else {
            tearDown()
            throw CoreAudioError.osStatus("AudioDeviceCreateIOProcIDWithBlock", status)
        }
        deviceProcID = procID

        status = AudioDeviceStart(aggregateDeviceID, procID)
        guard status == noErr else {
            tearDown()
            throw CoreAudioError.osStatus("AudioDeviceStart", status)
        }

        routerLog.notice("started routing pids=\(process.pids, privacy: .public) '\(process.name, privacy: .public)' -> '\(outputDevice.name, privacy: .public)' aggregateID=\(self.aggregateDeviceID, privacy: .public) tapID=\(self.tapID, privacy: .public)")
    }

    func stop() { tearDown() }

    private func tearDown() {
        if aggregateDeviceID.isValid, let deviceProcID {
            AudioDeviceStop(aggregateDeviceID, deviceProcID)
            AudioDeviceDestroyIOProcID(aggregateDeviceID, deviceProcID)
        }
        self.deviceProcID = nil

        if aggregateDeviceID.isValid {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = .unknown
        }

        if tapID.isValid {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = .unknown
        }
    }

    deinit { tearDown() }
}
