import Foundation

enum NowPlayingSource: String, CaseIterable, Sendable {
    case appleMusic = "com.apple.Music"
    case spotify = "com.spotify.client"

    var applicationName: String {
        switch self {
        case .appleMusic: "Music"
        case .spotify: "Spotify"
        }
    }
}

enum NowPlayingConnectionState: Equatable, Sendable {
    case notRunning
    case idle
    case connecting
    case connected
    case disconnected
    case permissionDenied
    case restartRequired

    var statusText: String {
        switch self {
        case .notRunning: "Not running"
        case .idle: "No active track"
        case .connecting: "Connecting…"
        case .connected: "Connected"
        case .disconnected: "Connection lost"
        case .permissionDenied: "Permission required"
        case .restartRequired: "Restart Notch Capture"
        }
    }

    var isRecoverable: Bool {
        self == .disconnected || self == .permissionDenied || self == .restartRequired
    }

    var canReconnect: Bool { self == .disconnected || self == .permissionDenied }
    var requiresSystemSettings: Bool { self == .permissionDenied }
    var requiresAppRestart: Bool { self == .restartRequired }
}

struct NowPlayingPresentation: Equatable, Sendable {
    let source: NowPlayingSource
    let state: NowPlayingConnectionState
    let snapshot: NowPlayingSnapshot

    var isRecovery: Bool { state.isRecoverable }
}

struct NowPlayingSnapshot: Equatable, Sendable {
    var source: NowPlayingSource
    var trackKey: String
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval
    var isPlaying: Bool
    var position: TimeInterval
    var positionAnchor: Date
    var artworkURL: URL?
    /// A recoverable connection failure keeps the last confirmed snapshot only
    /// as context. Its clock must never continue to imply live playback.
    var isFrozen = false

    func position(at date: Date) -> TimeInterval {
        let elapsed = isPlaying && !isFrozen ? date.timeIntervalSince(positionAnchor) : 0
        return min(max(0, position + elapsed), max(0, duration))
    }

    func progress(at date: Date) -> Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, position(at: date) / duration))
    }

    func position(at date: Date, previewing scrubFraction: Double?) -> TimeInterval {
        guard let scrubFraction else { return position(at: date) }
        return max(0, duration) * min(1, max(0, scrubFraction))
    }

    func seeking(to requestedPosition: TimeInterval, at date: Date) -> Self {
        var copy = self
        copy.position = min(max(0, requestedPosition), max(0, duration))
        copy.positionAnchor = date
        return copy
    }

    func frozen(at date: Date = .now) -> Self {
        var copy = self
        copy.position = position(at: date)
        copy.positionAnchor = date
        copy.isFrozen = true
        return copy
    }
}

enum MusicTimeFormatter {
    static func string(from seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "0:00" }
        let value = max(0, Int(seconds.rounded(.down)))
        let hours = value / 3_600
        let minutes = (value % 3_600) / 60
        let remainingSeconds = value % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        }
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }

    static func durationString(from duration: TimeInterval) -> String? {
        guard duration.isFinite, duration > 0 else { return nil }
        return string(from: duration)
    }
}
