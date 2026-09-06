import AppKit
import Foundation
import UniformTypeIdentifiers
import XCTest
@testable import NotchCapture

@MainActor
final class DropCaptureTests: XCTestCase {
    private struct ProviderFixture: Equatable {
        let result: Result<DropCapturePayload, DropCaptureFailure>

        static func success(_ payload: DropCapturePayload) -> Self {
            Self(result: .success(payload))
        }

        static func failure(_ failure: DropCaptureFailure) -> Self {
            Self(result: .failure(failure))
        }
    }

    func testConcreteJPEGAndHEICRepresentationsArePreserved() {
        let jpegData = Data([0xff, 0xd8, 0xff, 0xd9])
        let heicData = Data([0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70])

        let jpeg = DropCaptureImageRepresentation.materialize(
            data: jpegData,
            declaredType: .jpeg,
            suggestedName: "photo",
            index: 1
        )
        let heic = DropCaptureImageRepresentation.materialize(
            data: heicData,
            declaredType: .heic,
            suggestedName: "phone image.HEIC",
            index: 2
        )

        XCTAssertEqual(jpeg?.data, jpegData)
        XCTAssertEqual(jpeg?.typeIdentifier, UTType.jpeg.identifier)
        XCTAssertEqual(jpeg?.filename, "photo.jpeg")
        XCTAssertEqual(heic?.data, heicData)
        XCTAssertEqual(heic?.typeIdentifier, UTType.heic.identifier)
        XCTAssertEqual(heic?.filename, "phone image.HEIC")

        XCTAssertEqual(
            DropCaptureImageRepresentation.filename(
                suggestedName: "photo.jpg",
                type: .png,
                index: 3
            ),
            "photo.png"
        )
    }

    func testPreferredTypeChoosesConcreteRepresentationBeforeGenericImage() {
        XCTAssertEqual(
            DropCaptureImageRepresentation.preferredType(
                from: [UTType.image.identifier, UTType.heic.identifier]
            ),
            .heic
        )
        XCTAssertEqual(
            DropCaptureImageRepresentation.preferredType(
                from: [UTType.image.identifier, UTType.jpeg.identifier]
            ),
            .jpeg
        )
    }

    func testGenericImageIsTranscodedOnlyWhenNoConcreteTypeExists() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let source = try Data(contentsOf: root.appendingPathComponent("Design/reference-thumbnail.png"))

        let result = DropCaptureImageRepresentation.materialize(
            data: source,
            declaredType: .image,
            suggestedName: "unknown image.heic",
            index: 1
        )

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.typeIdentifier, UTType.png.identifier)
        XCTAssertEqual(result?.filename, "Dropped Image 1.png")
    }

    func testBatchTracksMixedResultsWithoutRetryingSuccessfulProviders() async {
        let fixtures = [
            ProviderFixture.success(.text("Keep this text")),
            ProviderFixture.failure(
                DropCaptureFailure(kind: .unreadable, providerIndex: 1, label: "Unreadable.png")
            ),
            ProviderFixture.success(.image(
                data: Data([0xff, 0xd8, 0xff, 0xd9]),
                typeIdentifier: UTType.jpeg.identifier,
                filename: "photo.jpeg"
            )),
            ProviderFixture.failure(
                DropCaptureFailure(kind: .unsupported, providerIndex: 3, label: "Unsupported.url")
            ),
        ]
        var loadCount = 0

        let batch = await DropCaptureProcessor.process(fixtures) { fixture, _ in
            loadCount += 1
            return fixture.result
        }

        XCTAssertEqual(loadCount, fixtures.count)
        XCTAssertEqual(batch.attemptedCount, 4)
        XCTAssertEqual(batch.succeededCount, 2)
        XCTAssertEqual(batch.failedCount, 2)
        XCTAssertFalse(batch.allFailed)
        XCTAssertEqual(
            batch.feedbackMessage,
            "Captured 2 items. 2 items couldn’t be read. Try dragging “Unreadable.png”, “Unsupported.url” again."
        )
    }

    func testAllFailedBatchHasDistinctRetryFeedback() async {
        let fixtures = [
            ProviderFixture.failure(
                DropCaptureFailure(kind: .unreadable, providerIndex: 0, label: "Broken.png")
            ),
            ProviderFixture.failure(
                DropCaptureFailure(kind: .unsupported, providerIndex: 1, label: "Missing.url")
            ),
        ]

        let batch = await DropCaptureProcessor.process(fixtures) { fixture, _ in
            fixture.result
        }

        XCTAssertTrue(batch.allFailed)
        XCTAssertEqual(
            batch.feedbackMessage,
            "Nothing was captured. The dropped items couldn’t be read. Try dragging “Broken.png”, “Missing.url” again."
        )
    }
}
