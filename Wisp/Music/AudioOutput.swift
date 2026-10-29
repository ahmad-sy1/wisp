import AudioToolbox
import CoreAudio

/// The default output device (speakers, AirPods…): its name and volume.
/// Read on demand while the Music tab is open; nothing runs in the background.
enum AudioOutput {
    struct Device {
        let id: AudioDeviceID
        let name: String
        let isBluetooth: Bool
    }

    static var current: Device? {
        guard let id = defaultDeviceID() else { return nil }
        var name: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        _ = withUnsafeMutablePointer(to: &name) {
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, $0)
        }
        var transport: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        address.mSelector = kAudioDevicePropertyTransportType
        AudioObjectGetPropertyData(id, &address, 0, nil, &size, &transport)
        let bluetooth = transport == kAudioDeviceTransportTypeBluetooth
            || transport == kAudioDeviceTransportTypeBluetoothLE
        return Device(id: id, name: name as String, isBluetooth: bluetooth)
    }

    /// 0…1, or nil when the device has no software volume.
    static var volume: Float? {
        guard let id = defaultDeviceID() else { return nil }
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        var address = volumeAddress
        guard AudioObjectHasProperty(id, &address),
              AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    static func setVolume(_ newValue: Float) {
        guard let id = defaultDeviceID() else { return }
        var value = Float32(min(1, max(0, newValue)))
        var address = volumeAddress
        AudioObjectSetPropertyData(id, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
    }

    private static var volumeAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                                   mScope: kAudioDevicePropertyScopeOutput,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private static func defaultDeviceID() -> AudioDeviceID? {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                                &address, 0, nil, &size, &id)
        return status == noErr && id != 0 ? id : nil
    }
}
