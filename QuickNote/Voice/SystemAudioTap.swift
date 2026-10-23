import Foundation
import CoreAudio
@preconcurrency import AVFoundation

/// Everything the Mac is playing (a WhatsApp, FaceTime or Zoom caller, say), joined with the default
/// microphone into one input device, so the recorder hears both sides of a call.
///
/// A global Core Audio process tap captures the system output; a private aggregate device pairs it
/// with the microphone. The first use asks for the system audio recording permission. Not a
/// per-app tap on purpose: it also hears music and notifications.
final class SystemAudioTap {
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var deviceID = AudioObjectID(kAudioObjectUnknown)

    /// Creates the tap and the aggregate device. Throws `VoiceRecorderError.systemAudioUnavailable`
    /// if either can't be made (permission refused, no microphone).
    init() throws {
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.uuid = UUID()
        description.muteBehavior = .unmuted
        guard AudioHardwareCreateProcessTap(description, &tapID) == noErr,
              let microphone = Self.defaultMicrophoneUID() else {
            throw VoiceRecorderError.systemAudioUnavailable
        }
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "QuickNote call capture",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: microphone,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: microphone]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: description.uuid.uuidString,
                kAudioSubTapDriftCompensationKey: true,
            ]],
        ]
        guard AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &deviceID) == noErr else {
            AudioHardwareDestroyProcessTap(tapID)
            throw VoiceRecorderError.systemAudioUnavailable
        }
    }

    deinit {
        AudioHardwareDestroyAggregateDevice(deviceID)
        AudioHardwareDestroyProcessTap(tapID)
    }

    /// Makes the engine read from the aggregate device instead of the default microphone. Call before
    /// asking the input node for its format.
    func route(_ engine: AVAudioEngine) throws {
        var device = deviceID
        guard let unit = engine.inputNode.audioUnit,
              AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                   &device, UInt32(MemoryLayout<AudioDeviceID>.size)) == noErr else {
            throw VoiceRecorderError.systemAudioUnavailable
        }
    }

    private static func defaultMicrophoneUID() -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown else { return nil }

        address.mSelector = kAudioDevicePropertyDeviceUID
        var uid: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &uid) == noErr else { return nil }
        return uid?.takeRetainedValue() as String?
    }
}
