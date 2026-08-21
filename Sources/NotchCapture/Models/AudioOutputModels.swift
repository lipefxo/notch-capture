import Foundation

enum AudioOutputTarget: String, CaseIterable, Identifiable, Sendable {
    case airPods
    case edifier
    case headphones

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .airPods: "AirPods"
        case .edifier: "Edifier"
        case .headphones: "Headphones"
        }
    }

    var systemDeviceName: String {
        switch self {
        case .airPods: "Felipe’s AirPods Pro"
        case .edifier: "EDIFIER M60"
        case .headphones: "fifine Ampli1"
        }
    }

    var symbolName: String {
        switch self {
        case .airPods: "airpodspro"
        case .edifier: "hifispeaker"
        case .headphones: "headphones"
        }
    }

    func matches(deviceName: String) -> Bool {
        Self.normalized(deviceName) == Self.normalized(systemDeviceName)
    }

    static func normalized(_ name: String) -> String {
        let folded = name.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        )
        return String(folded.filter { $0.isLetter || $0.isNumber }).lowercased()
    }
}

struct AudioOutputDevice: Equatable, Sendable {
    let id: UInt32
    let name: String
    let isAlive: Bool
    let hasOutput: Bool
    let canBeDefault: Bool
    let canBeSystemDefault: Bool

    var isSelectable: Bool {
        isAlive && hasOutput && canBeDefault && canBeSystemDefault
    }
}

struct AudioVolumeViewState: Equatable, Sendable {
    var value: Double?
    var isMuted: Bool
    var canSetVolume: Bool
    var canSetMute: Bool
    var deviceName: String?

    static let empty = Self(
        value: nil,
        isMuted: false,
        canSetVolume: false,
        canSetMute: false,
        deviceName: nil
    )

    static let preview = Self(
        value: 0.64,
        isMuted: false,
        canSetVolume: true,
        canSetMute: true,
        deviceName: AudioOutputTarget.edifier.systemDeviceName
    )

    var clampedValue: Double? {
        value.map { min(1, max(0, $0)) }
    }

    var isEffectivelyMuted: Bool {
        isMuted || (clampedValue ?? 1) <= 0.0001
    }

    var percentageText: String {
        guard let clampedValue else { return "Device controls" }
        return "\(Int((clampedValue * 100).rounded()))%"
    }

    var accessibilityValue: String {
        guard let clampedValue else {
            return deviceName.map { "Use controls on \($0)" } ?? "Use device controls"
        }
        let percentage = Int((clampedValue * 100).rounded())
        return isEffectivelyMuted ? "Muted, \(percentage)%" : "\(percentage)%"
    }
}

struct AudioOutputViewState: Equatable, Sendable {
    var availableTargets: Set<AudioOutputTarget>
    var mediaTarget: AudioOutputTarget?
    var systemTarget: AudioOutputTarget?
    var mediaDeviceName: String?
    var systemDeviceName: String?
    var volume: AudioVolumeViewState

    init(
        availableTargets: Set<AudioOutputTarget>,
        mediaTarget: AudioOutputTarget?,
        systemTarget: AudioOutputTarget?,
        mediaDeviceName: String?,
        systemDeviceName: String?,
        volume: AudioVolumeViewState = .empty
    ) {
        self.availableTargets = availableTargets
        self.mediaTarget = mediaTarget
        self.systemTarget = systemTarget
        self.mediaDeviceName = mediaDeviceName
        self.systemDeviceName = systemDeviceName
        self.volume = volume
    }

    static let empty = Self(
        availableTargets: [],
        mediaTarget: nil,
        systemTarget: nil,
        mediaDeviceName: nil,
        systemDeviceName: nil,
        volume: .empty
    )

    static let preview = Self(
        availableTargets: [.edifier, .headphones],
        mediaTarget: .edifier,
        systemTarget: .edifier,
        mediaDeviceName: AudioOutputTarget.edifier.systemDeviceName,
        systemDeviceName: AudioOutputTarget.edifier.systemDeviceName,
        volume: .preview
    )

    func isAvailable(_ target: AudioOutputTarget) -> Bool {
        availableTargets.contains(target)
    }

    func isSelected(_ target: AudioOutputTarget) -> Bool {
        mediaTarget == target && systemTarget == target
    }

    var accessibilityCurrentOutput: String {
        if let mediaTarget, mediaTarget == systemTarget {
            return mediaTarget.displayName
        }
        if mediaDeviceName == systemDeviceName, let mediaDeviceName {
            return mediaDeviceName
        }
        let media = mediaTarget?.displayName ?? mediaDeviceName ?? "Unknown"
        let system = systemTarget?.displayName ?? systemDeviceName ?? "Unknown"
        return "Media: \(media), system sounds: \(system)"
    }
}
