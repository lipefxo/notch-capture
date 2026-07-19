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

    func testScrubCommitUsesLastPreviewWhenReleaseLocationIsStale() {
        let committed = MusicScrubGeometry.committedFraction(
            previewing: 0.75,
            releaseX: 20,
            width: 100
        )

        XCTAssertEqual(committed, 0.75)
    }

    func testScrubCommitUsesReleaseLocationForClickAndClampsIt() {
        XCTAssertEqual(
            MusicScrubGeometry.committedFraction(
                previewing: nil,
                releaseX: 60,
                width: 100
            ),
            0.6
        )
        XCTAssertEqual(MusicScrubGeometry.fraction(at: -20, width: 100), 0)
        XCTAssertEqual(MusicScrubGeometry.fraction(at: 120, width: 100), 1)
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

    func testArtworkStillLoadsAfterCancelledRefreshForSameTrack() {
        // First launch often publishes metadata, then cancels mid-artwork fetch.
        // The follow-up refresh keeps the same track key and must still load art.
        XCTAssertTrue(
            NowPlayingService.needsArtworkLoad(trackKey: "track-1", artworkLoadedForTrackKey: nil)
        )
        XCTAssertTrue(
            NowPlayingService.needsArtworkLoad(trackKey: "track-1", artworkLoadedForTrackKey: "other")
        )
        XCTAssertFalse(
            NowPlayingService.needsArtworkLoad(trackKey: "track-1", artworkLoadedForTrackKey: "track-1")
        )
    }

    func testPollingIntervalsFavorNotificationDrivenUpdates() {
        XCTAssertNil(NowPlayingService.ActivityLevel.hidden.pollInterval)
        XCTAssertEqual(NowPlayingService.ActivityLevel.compact.pollInterval, 15)
        XCTAssertEqual(NowPlayingService.ActivityLevel.full.pollInterval, 5)
    }

    func testSnapshotPublicationIgnoresExpectedPositionAdvancement() {
        let anchor = Date(timeIntervalSinceReferenceDate: 100)
        let previous = makeSnapshot(source: .spotify, isPlaying: true, anchor: anchor)
        var candidate = previous
        candidate.position = 15
        candidate.positionAnchor = anchor.addingTimeInterval(5)

        XCTAssertFalse(NowPlayingService.shouldPublish(previous: previous, candidate: candidate))

        candidate.position = 17
        XCTAssertTrue(NowPlayingService.shouldPublish(previous: previous, candidate: candidate))
    }

    func testSnapshotPublicationIncludesSemanticPlaybackChanges() {
        let anchor = Date(timeIntervalSinceReferenceDate: 100)
        let previous = makeSnapshot(source: .spotify, isPlaying: true, anchor: anchor)
        var candidate = previous
        candidate.isPlaying = false
        XCTAssertTrue(NowPlayingService.shouldPublish(previous: previous, candidate: candidate))

        candidate = previous
        candidate.trackKey = "next-track"
        XCTAssertTrue(NowPlayingService.shouldPublish(previous: previous, candidate: candidate))
        XCTAssertTrue(NowPlayingService.shouldPublish(previous: nil, candidate: candidate))
        XCTAssertTrue(NowPlayingService.shouldPublish(previous: candidate, candidate: nil))
        XCTAssertFalse(NowPlayingService.shouldPublish(previous: nil, candidate: nil))
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

private actor BlockingAppleScriptRunner: AppleScriptRunning {
    private let response: AppleScriptResult
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private var runCount = 0

    init(response: AppleScriptResult) {
        self.response = response
    }

    func run(_: String) async throws -> AppleScriptResult {
        runCount += 1
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
        return response
    }

    func count() -> Int { runCount }

    func releaseNext() {
        guard !continuations.isEmpty else { return }
        continuations.removeFirst().resume()
    }
}

@MainActor
final class NowPlayingServiceRefreshTests: XCTestCase {
    func testRefreshesAreSingleFlightAndPendingTriggersCoalesce() async throws {
        let runner = BlockingAppleScriptRunner(response: .string(Self.spotifyStatus(position: 10)))
        let service = NowPlayingService(
            runner: runner,
            sourceIsRunning: { $0 == .spotify }
        )

        service.setActivityLevel(.compact)
        await waitUntil { await runner.count() == 1 }
        service.refresh()
        service.refresh(triggeredBy: .spotify)
        service.refresh()
        await Task.yield()
        let countWhileBlocked = await runner.count()
        XCTAssertEqual(countWhileBlocked, 1)

        await runner.releaseNext()
        await waitUntil { await runner.count() == 2 }
        let countAfterFollowUp = await runner.count()
        XCTAssertEqual(countAfterFollowUp, 2)

        await runner.releaseNext()
        service.stop()
    }

    func testHiddenActivityDiscardsAnInFlightRefresh() async throws {
        let runner = BlockingAppleScriptRunner(response: .string(Self.spotifyStatus(position: 10)))
        let service = NowPlayingService(
            runner: runner,
            sourceIsRunning: { $0 == .spotify }
        )
        var publishedSnapshots: [NowPlayingSnapshot?] = []
        service.onSnapshotChange = { publishedSnapshots.append($0) }

        service.setActivityLevel(.compact)
        await waitUntil { await runner.count() == 1 }
        service.setActivityLevel(.hidden)
        await runner.releaseNext()
        await Task.yield()
        await Task.yield()

        XCTAssertTrue(publishedSnapshots.isEmpty)
        XCTAssertNil(service.snapshot)
        service.stop()
    }

    private func waitUntil(
        attempts: Int = 100,
        _ predicate: () async -> Bool
    ) async {
        for _ in 0..<attempts {
            if await predicate() { return }
            await Task.yield()
        }
        XCTFail("Condition was not satisfied")
    }

    private static func spotifyStatus(position: Int) -> String {
        [
            "spotify:track:1",
            "Night Drive",
            "Cannons",
            "Fever Dream",
            "214000",
            String(position),
            "playing",
            "",
        ].joined(separator: "\u{1F}")
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

    func testPomodoroToggleIntentRoutesWithoutChangingSurface() {
        var toggleCount = 0
        var hooks = AppViewModel.Hooks()
        hooks.onPomodoroToggle = { toggleCount += 1 }
        let model = AppViewModel(
            surfaceState: .collapsedActivity,
            pomodoro: PomodoroState(
                duration: 25 * 60,
                phase: .running(endsAt: .now.addingTimeInterval(10 * 60))
            ),
            hooks: hooks
        )

        model.togglePomodoro()

        XCTAssertEqual(toggleCount, 1)
        XCTAssertEqual(model.surfaceState, .collapsedActivity)
    }

    func testPomodoroAccessibilityValueUsesSpokenUnits() {
        XCTAssertEqual(
            PomodoroCountdownLabel.accessibilityValue(61),
            "1 minute, 1 second remaining"
        )
        XCTAssertEqual(
            PomodoroCountdownLabel.accessibilityValue(24 * 60 + 23),
            "24 minutes, 23 seconds remaining"
        )
    }
}
