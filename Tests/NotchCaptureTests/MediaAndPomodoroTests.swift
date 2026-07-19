import XCTest
@testable import NotchCapture

final class NowPlayingModelTests: XCTestCase {
    func testMusicTimeFormatterUsesCompactTrackFormats() {
        XCTAssertEqual(MusicTimeFormatter.string(from: 0), "0:00")
        XCTAssertEqual(MusicTimeFormatter.string(from: 214), "3:34")
        XCTAssertEqual(MusicTimeFormatter.string(from: 3_723), "1:02:03")
        XCTAssertEqual(MusicTimeFormatter.string(from: -10), "0:00")
    }

    func testMusicTimeFormatterHidesUnavailableDuration() {
        XCTAssertNil(MusicTimeFormatter.durationString(from: 0))
        XCTAssertNil(MusicTimeFormatter.durationString(from: -1))
        XCTAssertNil(MusicTimeFormatter.durationString(from: .nan))
        XCTAssertEqual(MusicTimeFormatter.durationString(from: 214), "3:34")
    }

    func testPlayingPositionUsesAnchorAndClampsToDuration() {
        let anchor = Date(timeIntervalSinceReferenceDate: 100)
        let snapshot = NowPlayingSnapshot(
            source: .spotify,
            trackKey: "track",
            title: "Night Drive",
            artist: "Cannons",
            album: "Fever Dream",
            duration: 120,
            isPlaying: true,
            position: 115,
            positionAnchor: anchor,
            artworkURL: nil
        )

        XCTAssertEqual(snapshot.position(at: anchor.addingTimeInterval(2)), 117)
        XCTAssertEqual(snapshot.position(at: anchor.addingTimeInterval(20)), 120)
        XCTAssertEqual(snapshot.progress(at: anchor.addingTimeInterval(20)), 1)
    }

    func testPausedPositionDoesNotAdvance() {
        let anchor = Date(timeIntervalSinceReferenceDate: 100)
        var snapshot = makeSnapshot(source: .appleMusic, isPlaying: false, anchor: anchor)
        snapshot.position = 42

        XCTAssertEqual(snapshot.position(at: anchor.addingTimeInterval(30)), 42)
        XCTAssertEqual(snapshot.progress(at: anchor.addingTimeInterval(30)), 0.42)
    }

    func testScrubPreviewOverridesTimestampPositionAndClampsFraction() {
        let anchor = Date(timeIntervalSinceReferenceDate: 100)
        let snapshot = makeSnapshot(source: .spotify, isPlaying: true, anchor: anchor)
        let date = anchor.addingTimeInterval(30)

        XCTAssertEqual(snapshot.position(at: date, previewing: nil), 40)
        XCTAssertEqual(snapshot.position(at: date, previewing: 0.75), 75)
        XCTAssertEqual(snapshot.position(at: date, previewing: -1), 0)
        XCTAssertEqual(snapshot.position(at: date, previewing: 2), 100)
    }

    func testOptimisticSeekingClampsAndReanchorsPosition() {
        let anchor = Date(timeIntervalSinceReferenceDate: 100)
        let update = Date(timeIntervalSinceReferenceDate: 150)
        let snapshot = makeSnapshot(source: .spotify, isPlaying: true, anchor: anchor)

        let pastEnd = snapshot.seeking(to: 180, at: update)
        XCTAssertEqual(pastEnd.position, 100)
        XCTAssertEqual(pastEnd.positionAnchor, update)

        let beforeStart = snapshot.seeking(to: -15, at: update)
        XCTAssertEqual(beforeStart.position, 0)
        XCTAssertEqual(beforeStart.positionAnchor, update)
    }

    func testSpotifyParserNormalizesMilliseconds() throws {
        let separator = "\u{1F}"
        let raw = ["spotify:track:1", "Night Drive", "Cannons", "Fever Dream", "214000", "82", "playing", "https://i.scdn.co/image/abc"]
            .joined(separator: separator)
        let snapshot = try XCTUnwrap(NowPlayingService.parseStatus(raw, source: .spotify))

        XCTAssertEqual(snapshot.duration, 214)
        XCTAssertEqual(snapshot.position, 82)
        XCTAssertTrue(snapshot.isPlaying)
        XCTAssertEqual(snapshot.artworkURL?.host, "i.scdn.co")
    }

    func testAppleMusicParserAcceptsWhitespaceAndCommaDecimals() throws {
        let separator = "\u{1F}"
        let raw = ["music-track", "Lose Myself", "Zen/it", "Album", " 214,5 ", " 82,25 ", " PLAYING ", ""]
            .joined(separator: separator)
        let snapshot = try XCTUnwrap(NowPlayingService.parseStatus(raw, source: .appleMusic))

        XCTAssertEqual(snapshot.duration, 214.5)
        XCTAssertEqual(snapshot.position, 82.25)
        XCTAssertTrue(snapshot.isPlaying)
    }

    func testInvalidPlaybackNumbersKeepMetadataAndDisableProgress() throws {
        let separator = "\u{1F}"
        let raw = ["music-track", "Lose Myself", "Zen/it", "Album", "unknown", "unknown", "paused", ""]
            .joined(separator: separator)
        let snapshot = try XCTUnwrap(NowPlayingService.parseStatus(raw, source: .appleMusic))

        XCTAssertEqual(snapshot.duration, 0)
        XCTAssertEqual(snapshot.position, 0)
        XCTAssertEqual(snapshot.progress(at: .now), 0)
    }

    func testArbitrationPrefersTheOnlyPlayingSource() throws {
        let anchor = Date(timeIntervalSinceReferenceDate: 100)
        let music = makeSnapshot(source: .appleMusic, isPlaying: false, anchor: anchor)
        let spotify = makeSnapshot(source: .spotify, isPlaying: true, anchor: anchor)
        let selected = NowPlayingService.chooseActive(
            [music, spotify],
            currentSource: .appleMusic,
            lastActivity: [:]
        )
        XCTAssertEqual(selected?.source, .spotify)
    }

    private func makeSnapshot(source: NowPlayingSource, isPlaying: Bool, anchor: Date) -> NowPlayingSnapshot {
        NowPlayingSnapshot(
            source: source,
            trackKey: source.rawValue,
            title: "Track",
            artist: "Artist",
            album: "Album",
            duration: 100,
            isPlaying: isPlaying,
            position: 10,
            positionAnchor: anchor,
            artworkURL: nil
        )
    }
}

@MainActor
final class PomodoroServiceTests: XCTestCase {
    func testStartPauseResumeAndResetUseWallClockAnchors() {
        var current = Date(timeIntervalSinceReferenceDate: 1_000)
        let service = PomodoroService(duration: 25 * 60, now: { current })

        service.start()
        current = current.addingTimeInterval(60)
        service.pause()
        XCTAssertEqual(service.state.remaining(at: current), 24 * 60)

        current = current.addingTimeInterval(30)
        service.resume()
        XCTAssertEqual(service.state.remaining(at: current), 24 * 60)

        service.reset()
        XCTAssertEqual(service.state.phase, .idle)
        XCTAssertEqual(service.state.remaining(at: current), 25 * 60)
    }

    func testDurationIsClampedAndPersisted() {
        var persisted: TimeInterval?
        let service = PomodoroService(persistDuration: { persisted = $0 })
        service.setDuration(10)

        XCTAssertEqual(service.state.duration, PomodoroState.durationRange.lowerBound)
        XCTAssertEqual(persisted, PomodoroState.durationRange.lowerBound)
    }
}

@MainActor
final class LiveActivityViewModelTests: XCTestCase {
    func testDismissUsesActivitySurfaceWhileMusicExists() {
        let snapshot = NowPlayingSnapshot(
            source: .spotify,
            trackKey: "track",
            title: "Track",
            artist: "Artist",
            album: "Album",
            duration: 100,
            isPlaying: true,
            position: 0,
            positionAnchor: .now,
            artworkURL: nil
        )
        let model = AppViewModel(surfaceState: .expanded, nowPlaying: snapshot)
        model.dismiss()
        XCTAssertEqual(model.surfaceState, .collapsedActivity)
    }

    func testMusicIntentsRouteThroughHooksWithoutChangingSurface() {
        var previousCount = 0
        var toggleCount = 0
        var nextCount = 0
        var seekPosition: TimeInterval?
        var hooks = AppViewModel.Hooks()
        hooks.onMusicPrevious = { previousCount += 1 }
        hooks.onMusicPlayPause = { toggleCount += 1 }
        hooks.onMusicNext = { nextCount += 1 }
        hooks.onMusicSeek = { seekPosition = $0 }
        let model = AppViewModel(surfaceState: .collapsedActivity, hooks: hooks)

        model.musicPrevious()
        model.musicPlayPause()
        model.musicNext()
        model.musicSeek(to: 91)

        XCTAssertEqual(previousCount, 1)
        XCTAssertEqual(toggleCount, 1)
        XCTAssertEqual(nextCount, 1)
        XCTAssertEqual(seekPosition, 91)
        XCTAssertEqual(model.surfaceState, .collapsedActivity)
    }
}
