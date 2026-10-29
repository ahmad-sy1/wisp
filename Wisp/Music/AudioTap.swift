import AudioToolbox
import CoreAudio
import Foundation

/// Listens to the audio of one app (and its helper processes) through a Core Audio
/// process tap (macOS 14.2+). Nothing is recorded or stored: each block goes straight
/// into the analyser and is dropped.
///
/// The first tap triggers macOS's "System Audio Recording" permission prompt.
final class AudioTap: @unchecked Sendable {
    enum TapError: Error { case noProcess, tap(OSStatus), aggregate(OSStatus), start(OSStatus) }

    private let queue = DispatchQueue(label: "wisp.audio-tap", qos: .userInteractive)
    private let analyzer = SpectrumAnalyzer()
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var mono: [Float] = []

    /// Starts listening to every audio process whose bundle id starts with
    /// `bundlePrefix` (a browser plays through helper processes such as
    /// `com.brave.Browser.helper`), or to all audio when it is nil.
    func start(bundlePrefix: String?, onFrame: @escaping @Sendable (SpectrumFrame) -> Void) throws {
        stop()

        let description: CATapDescription
        if let bundlePrefix {
            let processes = Self.audioProcesses(matching: bundlePrefix)
            guard !processes.isEmpty else { throw TapError.noProcess }
            description = CATapDescription(stereoMixdownOfProcesses: processes)
        } else {
            description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        }
        description.uuid = UUID()
        description.name = "wisp spectrum"
        description.isPrivate = true
        description.muteBehavior = .unmuted

        var tap = AudioObjectID(kAudioObjectUnknown)
        var status = AudioHardwareCreateProcessTap(description, &tap)
        guard status == noErr else { throw TapError.tap(status) }
        tapID = tap

        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "wisp spectrum",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString,
                                               kAudioSubTapDriftCompensationKey: true]],
        ]
        var device = AudioObjectID(kAudioObjectUnknown)
        status = AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &device)
        guard status == noErr else { stop(); throw TapError.aggregate(status) }
        aggregateID = device

        let format = Self.tapFormat(tap)
        let rate = format.mSampleRate > 0 ? format.mSampleRate : 48_000
        let analyzer = self.analyzer

        var proc: AudioDeviceIOProcID?
        status = AudioDeviceCreateIOProcIDWithBlock(&proc, device, queue) { [weak self] _, input, _, _, _ in
            guard let self else { return }
            let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
            guard let first = buffers.first, let data = first.mData else { return }
            let frames = Int(first.mDataByteSize) / (MemoryLayout<Float>.size * max(1, Int(first.mNumberChannels)))
            guard frames > 0 else { return }
            if self.mono.count < frames { self.mono = [Float](repeating: 0, count: frames) }

            // Interleaved float input → mono.
            let samples = data.assumingMemoryBound(to: Float.self)
            let stride = Int(first.mNumberChannels)
            self.mono.withUnsafeMutableBufferPointer { out in
                for i in 0..<frames {
                    var sum: Float = 0
                    for c in 0..<stride { sum += samples[i * stride + c] }
                    out[i] = sum / Float(stride)
                }
                if let frame = analyzer.process(UnsafeBufferPointer(rebasing: out[0..<frames]), sampleRate: rate) {
                    onFrame(frame)
                }
            }
        }
        guard status == noErr, let proc else { stop(); throw TapError.start(status) }
        procID = proc

        status = AudioDeviceStart(device, proc)
        guard status == noErr else { stop(); throw TapError.start(status) }
    }

    func stop() {
        if aggregateID != kAudioObjectUnknown {
            if let procID {
                AudioDeviceStop(aggregateID, procID)
                AudioDeviceDestroyIOProcID(aggregateID, procID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        procID = nil
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
    }

    deinit { stop() }

    // MARK: - Core Audio lookups

    private static func audioProcesses(matching prefix: String) -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }

        return ids.filter { id in
            var bundleAddress = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyBundleID,
                                                           mScope: kAudioObjectPropertyScopeGlobal,
                                                           mElement: kAudioObjectPropertyElementMain)
            var bundle: CFString = "" as CFString
            var bundleSize = UInt32(MemoryLayout<CFString>.size)
            let ok = withUnsafeMutablePointer(to: &bundle) {
                AudioObjectGetPropertyData(id, &bundleAddress, 0, nil, &bundleSize, $0)
            }
            return ok == noErr && (bundle as String).hasPrefix(prefix)
        }
    }

    private static func tapFormat(_ tap: AudioObjectID) -> AudioStreamBasicDescription {
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &format)
        return format
    }
}
