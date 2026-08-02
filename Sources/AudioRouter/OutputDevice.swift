import AudioToolbox

struct OutputDevice: Identifiable, Hashable {
    let objectID: AudioObjectID
    let uid: String
    let name: String
    let transportType: UInt32

    var id: String { uid }

    /// SF Symbol matching the device's physical connection, mirroring how SoundSource
    /// distinguishes built-in speakers, headphones, Bluetooth, HDMI displays, etc.
    var symbolName: String {
        switch transportType {
        case kAudioDeviceTransportTypeBuiltIn:
            return "hifispeaker.fill"
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            return "headphones"
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort:
            return "tv"
        case kAudioDeviceTransportTypeUSB:
            return "cable.connector"
        case kAudioDeviceTransportTypeAirPlay:
            return "airplayaudio"
        default:
            return "speaker.wave.2.fill"
        }
    }

    static func listAll() -> [OutputDevice] {
        guard let deviceIDs = try? SystemAudioObject.allDevices() else { return [] }
        return deviceIDs.compactMap { deviceID in
            guard deviceID.outputChannelCount() > 0,
                  let uid = deviceID.readString(kAudioDevicePropertyDeviceUID),
                  let name = deviceID.readString(kAudioObjectPropertyName),
                  !name.hasPrefix("AudioRouter-")
            else { return nil }
            let transportType = (try? deviceID.read(kAudioDevicePropertyTransportType, as: UInt32(0), context: "transportType")) ?? 0
            return OutputDevice(objectID: deviceID, uid: uid, name: name, transportType: transportType)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func systemDefault() -> OutputDevice? {
        guard let deviceID = try? SystemAudioObject.defaultOutputDevice(),
              deviceID.isValid,
              let uid = deviceID.readString(kAudioDevicePropertyDeviceUID),
              let name = deviceID.readString(kAudioObjectPropertyName)
        else { return nil }
        let transportType = (try? deviceID.read(kAudioDevicePropertyTransportType, as: UInt32(0), context: "transportType")) ?? 0
        return OutputDevice(objectID: deviceID, uid: uid, name: name, transportType: transportType)
    }
}
