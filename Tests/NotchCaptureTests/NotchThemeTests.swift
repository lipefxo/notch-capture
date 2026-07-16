import XCTest
@testable import NotchCapture

final class NotchThemeTests: XCTestCase {
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
