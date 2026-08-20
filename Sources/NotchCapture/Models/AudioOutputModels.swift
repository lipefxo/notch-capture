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

struct AudioOutputViewState: Equatable, Sendable {
    var availableTargets: Set<AudioOutputTarget>
    var mediaTarget: AudioOutputTarget?
    var systemTarget: AudioOutputTarget?
    var mediaDeviceName: String?
    var systemDeviceName: String?

    static let empty = Self(
        availableTargets: [],
        mediaTarget: nil,
        systemTarget: nil,
        mediaDeviceName: nil,
        systemDeviceName: nil
    )

    static let preview = Self(
        availableTargets: [.edifier, .headphones],
        mediaTarget: .edifier,
        systemTarget: .edifier,
        mediaDeviceName: AudioOutputTarget.edifier.systemDeviceName,
        systemDeviceName: AudioOutputTarget.edifier.systemDeviceName
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
