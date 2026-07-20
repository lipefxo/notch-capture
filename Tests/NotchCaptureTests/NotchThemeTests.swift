import AppKit
import XCTest
@testable import NotchCapture

final class NotchThemeTests: XCTestCase {
    func testArtworkOverlayUsesWhiteForDarkCenterFootprint() throws {
        let dark = ArtworkOverlayColor.Sample(red: 0.10, green: 0.12, blue: 0.14, alpha: 1)

        try assertArtworkOverlayColor(
            ArtworkOverlayColor.resolvedColor(from: Array(repeating: dark, count: 40)),
            red: 1,
            green: 1,
            blue: 1
        )
    }

    func testArtworkOverlayUsesBlackForBrightCenterFootprint() throws {
        let bright = ArtworkOverlayColor.Sample(red: 0.92, green: 0.88, blue: 0.80, alpha: 1)

        try assertArtworkOverlayColor(
            ArtworkOverlayColor.resolvedColor(from: Array(repeating: bright, count: 40)),
            red: 0,
            green: 0,
            blue: 0
        )
    }

    func testArtworkOverlaySamplesOnlyTheCenteredControlFootprint() throws {
        let image = NSImage(size: NSSize(width: 100, height: 100))
        image.lockFocus()
        NSColor.black.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 100, height: 100)).fill()
        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(x: 21, y: 21, width: 58, height: 58)).fill()
        image.unlockFocus()

        try assertArtworkOverlayColor(
            ArtworkOverlayColor.color(from: image),
            red: 0,
            green: 0,
            blue: 0
        )
    }

    func testArtworkOverlayUsesWhiteAtLuminanceThresholdAndBlackImmediatelyAboveIt() throws {
        let atThreshold = ArtworkOverlayColor.Sample(red: 0.46, green: 0.46, blue: 0.46, alpha: 1)
        let aboveThreshold = ArtworkOverlayColor.Sample(red: 0.461, green: 0.461, blue: 0.461, alpha: 1)

        try assertArtworkOverlayColor(
            ArtworkOverlayColor.resolvedColor(from: [atThreshold]),
            red: 1,
            green: 1,
            blue: 1
        )
        try assertArtworkOverlayColor(
            ArtworkOverlayColor.resolvedColor(from: [aboveThreshold]),
            red: 0,
            green: 0,
            blue: 0
        )
    }

    func testArtworkOverlayIgnoresFullyTransparentCenterSamples() throws {
        let transparentDark = ArtworkOverlayColor.Sample(red: 0, green: 0, blue: 0, alpha: 0)
        let bright = ArtworkOverlayColor.Sample(red: 0.95, green: 0.95, blue: 0.95, alpha: 1)

        try assertArtworkOverlayColor(
            ArtworkOverlayColor.resolvedColor(from: [transparentDark, bright]),
            red: 0,
            green: 0,
            blue: 0
        )
    }

    func testArtworkOverlayFallsBackToWhiteWithoutReadableArtwork() throws {
        XCTAssertNil(
            ArtworkOverlayColor.resolvedColor(from: [
                ArtworkOverlayColor.Sample(red: 0, green: 0, blue: 0, alpha: 0)
            ])
        )
        try assertArtworkOverlayColor(
            ArtworkOverlayColor.color(from: nil),
            red: 1,
            green: 1,
            blue: 1
        )
    }

    func testArtworkOverlayUsesAlphaWeightedMixedCenterSamples() throws {
        let dark = ArtworkOverlayColor.Sample(red: 0.10, green: 0.10, blue: 0.10, alpha: 1)
        let bright = ArtworkOverlayColor.Sample(red: 0.95, green: 0.95, blue: 0.95, alpha: 0.2)

        try assertArtworkOverlayColor(
            ArtworkOverlayColor.resolvedColor(from: [dark, bright]),
            red: 1,
            green: 1,
            blue: 1
        )
    }

    func testTagPaletteIndexCoversEveryPaletteBucket() {
        for expectedIndex in 0..<6 {
            let seedAtBucketCenter = (Double(expectedIndex) + 0.5) / 6
            XCTAssertEqual(NotchTheme.tagPaletteIndex(seed: seedAtBucketCenter), expectedIndex)
        }
    }

    func testTagPaletteIndexUsesDeterministicBoundaries() {
        for expectedIndex in 1..<6 {
            let boundary = Double(expectedIndex) / 6
            XCTAssertEqual(NotchTheme.tagPaletteIndex(seed: boundary - 1e-12), expectedIndex - 1)
            XCTAssertEqual(NotchTheme.tagPaletteIndex(seed: boundary), expectedIndex)
        }
    }

    func testTagPaletteIndexWrapsPositiveAndNegativeSeeds() {
        XCTAssertEqual(NotchTheme.tagPaletteIndex(seed: 0), 0)
        XCTAssertEqual(NotchTheme.tagPaletteIndex(seed: 1), 0)
        XCTAssertEqual(NotchTheme.tagPaletteIndex(seed: 1.25), 1)
        XCTAssertEqual(NotchTheme.tagPaletteIndex(seed: -0.01), 5)
        XCTAssertEqual(NotchTheme.tagPaletteIndex(seed: -1), 0)
    }

    func testPomodoroTimerColorUsesPrimaryWhiteThroughTheFirstHalf() {
        assertPomodoroColor(
            NotchTheme.pomodoroTimerColor(remaining: 25 * 60, duration: 25 * 60),
            red: 1,
            green: 1,
            blue: 1
        )
        assertPomodoroColor(
            NotchTheme.pomodoroTimerColor(remaining: 12.5 * 60, duration: 25 * 60),
            red: 1,
            green: 1,
            blue: 1
        )
        assertPomodoroColor(
            NotchTheme.pomodoroTimerColor(remaining: 30 * 60, duration: 25 * 60),
            red: 1,
            green: 1,
            blue: 1
        )
    }

    func testPomodoroTimerColorInterpolatesPrimaryWhiteToAmber() {
        assertPomodoroColor(
            NotchTheme.pomodoroTimerColor(remaining: 8.75 * 60, duration: 25 * 60),
            red: 1,
            green: 0.75,
            blue: 0.5
        )
        assertPomodoroColor(
            NotchTheme.pomodoroTimerColor(remaining: 5 * 60, duration: 25 * 60),
            red: 1,
            green: 0.5,
            blue: 0
        )
    }

    func testPomodoroTimerColorInterpolatesAmberToRed() {
        assertPomodoroColor(
            NotchTheme.pomodoroTimerColor(remaining: 2.5 * 60, duration: 25 * 60),
            red: 1,
            green: 0.25,
            blue: 0
        )
        assertPomodoroColor(
            NotchTheme.pomodoroTimerColor(remaining: 0, duration: 25 * 60),
            red: 1,
            green: 0,
            blue: 0
        )
        assertPomodoroColor(
            NotchTheme.pomodoroTimerColor(remaining: -60, duration: 25 * 60),
            red: 1,
            green: 0,
            blue: 0
        )
    }

    func testPomodoroTimerColorTreatsInvalidDurationsAsCritical() {
        for duration in [0, -60, .infinity, .nan] {
            assertPomodoroColor(
                NotchTheme.pomodoroTimerColor(remaining: 60, duration: duration),
                red: 1,
                green: 0,
                blue: 0
            )
        }
    }

    private func assertPomodoroColor(
        _ color: NotchTheme.PomodoroTimerColor,
        red: Double,
        green: Double,
        blue: Double,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(color.red, red, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(color.green, green, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(color.blue, blue, accuracy: 0.000_001, file: file, line: line)
    }

    private func assertArtworkOverlayColor(
        _ color: NSColor?,
        red: CGFloat,
        green: CGFloat,
        blue: CGFloat,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let color = try XCTUnwrap(color, file: file, line: line)
        var resolvedRed: CGFloat = 0
        var resolvedGreen: CGFloat = 0
        var resolvedBlue: CGFloat = 0
        var alpha: CGFloat = 0
        guard let sRGBColor = color.usingColorSpace(.sRGB) else {
            XCTFail("Expected an sRGB color.", file: file, line: line)
            return
        }
        sRGBColor.getRed(
            &resolvedRed,
            green: &resolvedGreen,
            blue: &resolvedBlue,
            alpha: &alpha
        )
        XCTAssertEqual(resolvedRed, red, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(resolvedGreen, green, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(resolvedBlue, blue, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(alpha, 1, accuracy: 0.000_001, file: file, line: line)
    }
}
