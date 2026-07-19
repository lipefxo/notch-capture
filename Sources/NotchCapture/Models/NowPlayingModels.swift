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

    func position(at date: Date) -> TimeInterval {
        let elapsed = isPlaying ? date.timeIntervalSince(positionAnchor) : 0
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

struct PomodoroState: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case idle
        case running(endsAt: Date)
        case paused(remaining: TimeInterval)
        case finished
    }

    static let defaultDuration: TimeInterval = 25 * 60
    static let durationRange: ClosedRange<TimeInterval> = 60...(180 * 60)

    var duration: TimeInterval = Self.defaultDuration
    var phase: Phase = .idle

    func remaining(at date: Date) -> TimeInterval {
        switch phase {
        case .idle: duration
        case let .running(endsAt): max(0, endsAt.timeIntervalSince(date))
        case let .paused(remaining): max(0, remaining)
        case .finished: 0
        }
    }

    func progress(at date: Date) -> Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, 1 - (remaining(at: date) / duration)))
    }

    var isActive: Bool {
        switch phase {
        case .idle: false
        case .running, .paused, .finished: true
        }
    }
}
