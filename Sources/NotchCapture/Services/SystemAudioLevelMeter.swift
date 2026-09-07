import AppKit
import CoreAudio
import Foundation

/// Reads the active music application's output without rerouting or muting it.
/// Core Audio process taps are available from macOS 14.2; older systems and
/// denied capture permission simply leave the artwork waveform at rest.
final class SystemAudioLevelMeter: @unchecked Sendable {
    var onLevelsChange: (@MainActor @Sendable (MusicWaveformLevels) -> Void)?

    private let ioQueue = DispatchQueue(label: "com.lipe.notchcapture.audio-meter", qos: .userInteractive)
    private let stateLock = NSLock()
    private var source: NowPlayingSource?
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var streamFormat = AudioStreamBasicDescription()
    private var levels = MusicWaveformLevels.silent
    private var smoothedLevel = 0.0
    private var lastEmission = 0.0

    func monitor(_ newSource: NowPlayingSource?) {
        stateLock.lock()
        let isUnchanged = source == newSource
        stateLock.unlock()
        guard !isUnchanged else { return }

        stop()
        guard let newSource else { return }

        stateLock.lock()
        source = newSource
        stateLock.unlock()

        guard #available(macOS 14.2, *),
              let processID = Self.processObjectID(for: newSource) else {
            return
        }
        startTap(processID: processID)
    }

    func stop() {
        stateLock.lock()
        let deviceID = aggregateDeviceID
        let procID = ioProcID
        let currentTapID = tapID
        aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
        ioProcID = nil
        tapID = AudioObjectID(kAudioObjectUnknown)
        source = nil
        levels = .silent
        smoothedLevel = 0
        lastEmission = 0
        stateLock.unlock()

        if deviceID != kAudioObjectUnknown, let procID {
            AudioDeviceStop(deviceID, procID)
            AudioDeviceDestroyIOProcID(deviceID, procID)
        }
        if deviceID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(deviceID)
        }
        if currentTapID != kAudioObjectUnknown, #available(macOS 14.2, *) {
            AudioHardwareDestroyProcessTap(currentTapID)
        }
        publish(.silent)
    }

    @available(macOS 14.2, *)
    private func startTap(processID: AudioObjectID) {
        let description = CATapDescription(stereoMixdownOfProcesses: [processID])
        description.name = "Notch Capture Music Meter"
        description.isPrivate = true
        description.muteBehavior = .unmuted

        var newTapID = AudioObjectID(kAudioObjectUnknown)
        guard AudioHardwareCreateProcessTap(description, &newTapID) == noErr else { return }

        var format = AudioStreamBasicDescription()
        var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var formatAddress = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(
            newTapID,
            &formatAddress,
            0,
            nil,
            &formatSize,
            &format
        ) == noErr,
              format.mFormatID == kAudioFormatLinearPCM,
              format.mFormatFlags & kAudioFormatFlagIsFloat != 0 else {
            AudioHardwareDestroyProcessTap(newTapID)
            return
        }

        let aggregateUID = "com.lipe.notchcapture.audio-meter.\(UUID().uuidString)"
        let configuration: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Notch Capture Music Meter",
            kAudioAggregateDeviceUIDKey: aggregateUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: description.uuid.uuidString,
                kAudioSubTapDriftCompensationKey: true,
            ]],
        ]

        var deviceID = AudioObjectID(kAudioObjectUnknown)
        guard AudioHardwareCreateAggregateDevice(configuration as CFDictionary, &deviceID) == noErr else {
            AudioHardwareDestroyProcessTap(newTapID)
            return
        }

        var newIOProcID: AudioDeviceIOProcID?
        let createStatus = AudioDeviceCreateIOProcIDWithBlock(
            &newIOProcID,
            deviceID,
            ioQueue
        ) { [weak self] _, inputData, _, _, _ in
            self?.consume(inputData)
        }
        guard createStatus == noErr, let newIOProcID else {
            AudioHardwareDestroyAggregateDevice(deviceID)
            AudioHardwareDestroyProcessTap(newTapID)
            return
        }

        stateLock.lock()
        tapID = newTapID
        aggregateDeviceID = deviceID
        ioProcID = newIOProcID
        streamFormat = format
        stateLock.unlock()

        guard AudioDeviceStart(deviceID, newIOProcID) == noErr else {
            stop()
            return
        }
    }

    private func consume(_ inputData: UnsafePointer<AudioBufferList>) {
        stateLock.lock()
        let isFloat = streamFormat.mFormatFlags & kAudioFormatFlagIsFloat != 0
        stateLock.unlock()
        guard isFloat else { return }

        let buffers = UnsafeMutableAudioBufferListPointer(
            UnsafeMutablePointer(mutating: inputData)
        )
        var sumOfSquares = 0.0
        var sampleCount = 0
        for buffer in buffers {
            guard let data = buffer.mData else { continue }
            let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            let samples = data.assumingMemoryBound(to: Float.self)
            for index in 0..<count {
                let sample = Double(samples[index])
                guard sample.isFinite else { continue }
                sumOfSquares += sample * sample
                sampleCount += 1
            }
        }
        guard sampleCount > 0 else { return }

        let rms = sqrt(sumOfSquares / Double(sampleCount))
        let decibels = 20 * log10(max(rms, 0.000_001))
        let normalized = min(1, max(0, (decibels + 55) / 45))
        let now = ProcessInfo.processInfo.systemUptime

        stateLock.lock()
        let smoothing = normalized > smoothedLevel ? 0.58 : 0.16
        smoothedLevel += (normalized - smoothedLevel) * smoothing
        guard now - lastEmission >= 1 / 20 else {
            stateLock.unlock()
            return
        }
        lastEmission = now
        levels = levels.appending(smoothedLevel)
        let nextLevels = levels
        stateLock.unlock()
        publish(nextLevels)
    }

    private func publish(_ levels: MusicWaveformLevels) {
        guard let onLevelsChange else { return }
        DispatchQueue.main.async {
            onLevelsChange(levels)
        }
    }

    private static func processObjectID(for source: NowPlayingSource) -> AudioObjectID? {
        guard let application = NSRunningApplication.runningApplications(
            withBundleIdentifier: source.rawValue
        ).first else {
            return nil
        }
        var pid = application.processIdentifier
        var processID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = withUnsafePointer(to: &pid) { qualifier in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                UInt32(MemoryLayout<pid_t>.size),
                qualifier,
                &size,
                &processID
            )
        }
        guard status == noErr, processID != kAudioObjectUnknown else { return nil }
        return processID
    }
}
