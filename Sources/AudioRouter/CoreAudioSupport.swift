import Foundation
import CoreAudio
import AudioToolbox

enum CoreAudioError: LocalizedError {
    case osStatus(String, OSStatus)
    case invalidObject(String)

    var errorDescription: String? {
        switch self {
        case .osStatus(let context, let status):
            return "\(context) failed (OSStatus \(status))"
        case .invalidObject(let context):
            return "\(context): invalid audio object"
        }
    }
}

extension AudioObjectID {
    static let systemObject = AudioObjectID(kAudioObjectSystemObject)
    static let unknown = kAudioObjectUnknown

    var isValid: Bool { self != .unknown }

    /// Generic fixed-size property read (structs, scalars, CFTypes via bridging).
    func read<T>(_ selector: AudioObjectPropertySelector,
                 scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                 element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain,
                 as defaultValue: T,
                 context: String) throws -> T {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
        var size = UInt32(MemoryLayout<T>.size)
        var value = defaultValue
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(self, &address, 0, nil, &size, $0)
        }
        guard status == noErr else { throw CoreAudioError.osStatus(context, status) }
        return value
    }

    /// Generic variable-length array property read.
    func readArray<T>(_ selector: AudioObjectPropertySelector,
                       scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                       element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain,
                       elementType: T.Type,
                       context: String) throws -> [T] {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(self, &address, 0, nil, &size)
        guard status == noErr else { throw CoreAudioError.osStatus("\(context) (size)", status) }
        guard size > 0 else { return [] }

        let count = Int(size) / MemoryLayout<T>.size
        var values = [T](repeating: unsafeBitCast(0 as Int32, to: T.self), count: count)
        status = values.withUnsafeMutableBytes { ptr in
            AudioObjectGetPropertyData(self, &address, 0, nil, &size, ptr.baseAddress!)
        }
        guard status == noErr else { throw CoreAudioError.osStatus(context, status) }
        return values
    }

    func readString(_ selector: AudioObjectPropertySelector,
                     scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                     element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(self, &address, 0, nil, &size) == noErr, size > 0 else { return nil }
        var cfValue: CFString = "" as CFString
        let status = withUnsafeMutablePointer(to: &cfValue) {
            AudioObjectGetPropertyData(self, &address, 0, nil, &size, $0)
        }
        guard status == noErr else { return nil }
        return cfValue as String
    }

    func readBool(_ selector: AudioObjectPropertySelector,
                   scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> Bool {
        (try? read(selector, scope: scope, as: UInt32(0), context: "readBool")) == 1
    }

    func readPID(_ selector: AudioObjectPropertySelector) -> pid_t? {
        try? read(selector, as: pid_t(-1), context: "readPID")
    }

    /// Generic fixed-size property write.
    func write<T>(_ selector: AudioObjectPropertySelector,
                   scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                   element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain,
                   value: T,
                   context: String) throws {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
        var v = value
        let status = AudioObjectSetPropertyData(self, &address, 0, nil, UInt32(MemoryLayout<T>.size), &v)
        guard status == noErr else { throw CoreAudioError.osStatus(context, status) }
    }

    /// Number of output channels this device exposes (0 for input-only devices).
    func outputChannelCount() -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(self, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let listPtr = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
        defer { listPtr.deallocate() }
        guard AudioObjectGetPropertyData(self, &address, 0, nil, &size, listPtr) == noErr else { return 0 }
        let buffers = UnsafeMutableAudioBufferListPointer(listPtr)
        return buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
    }
}

enum SystemAudioObject {
    static func processObjectList() throws -> [AudioObjectID] {
        try AudioObjectID.systemObject.readArray(
            kAudioHardwarePropertyProcessObjectList,
            elementType: AudioObjectID.self,
            context: "processObjectList"
        )
    }

    static func defaultOutputDevice() throws -> AudioObjectID {
        try AudioObjectID.systemObject.read(
            kAudioHardwarePropertyDefaultOutputDevice,
            as: AudioObjectID.unknown,
            context: "defaultOutputDevice"
        )
    }

    static func allDevices() throws -> [AudioObjectID] {
        try AudioObjectID.systemObject.readArray(
            kAudioHardwarePropertyDevices,
            elementType: AudioObjectID.self,
            context: "allDevices"
        )
    }

    /// Sets the system's default output device (both "media" and "system/alert
    /// sounds" defaults, matching what System Settings does when you pick a device).
    static func setDefaultOutputDevice(_ deviceID: AudioObjectID) throws {
        try AudioObjectID.systemObject.write(kAudioHardwarePropertyDefaultOutputDevice, value: deviceID, context: "setDefaultOutputDevice")
        try? AudioObjectID.systemObject.write(kAudioHardwarePropertyDefaultSystemOutputDevice, value: deviceID, context: "setDefaultSystemOutputDevice")
    }
}
