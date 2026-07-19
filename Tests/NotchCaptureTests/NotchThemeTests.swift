import XCTest
@testable import NotchCapture

final class NotchThemeTests: XCTestCase {
    func testArtworkAccentUsesDominantChromaticHue() throws {
        let blue = ArtworkAccentColor.Sample(red: 0.05, green: 0.25, blue: 0.95, alpha: 1)
        let red = ArtworkAccentColor.Sample(red: 0.95, green: 0.08, blue: 0.04, alpha: 1)
        let samples = Array(repeating: blue, count: 80) + Array(repeating: red, count: 20)

        let color = try XCTUnwrap(ArtworkAccentColor.resolvedColor(from: samples))
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        XCTAssertEqual(hue, 2.0 / 3.0, accuracy: 0.05)
        XCTAssertGreaterThan(saturation, 0.5)
        XCTAssertGreaterThan(brightness, 0.9)
    }

    func testArtworkAccentFallsBackToNeutralForMonochromeArtwork() throws {
        let gray = ArtworkAccentColor.Sample(red: 0.45, green: 0.45, blue: 0.45, alpha: 1)
        let color = try XCTUnwrap(ArtworkAccentColor.resolvedColor(from: Array(repeating: gray, count: 40)))

        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        XCTAssertEqual(saturation, 0, accuracy: 0.01)
        XCTAssertGreaterThan(brightness, 0.9)
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
}
