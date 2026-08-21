import XCTest
@testable import NotchCapture

final class NotchPresentationTests: XCTestCase {
    func testPopoverPlacementClampsToPanelMargins() {
        let frame = NotchPopoverPlacement.frame(
            anchor: CGRect(x: 400, y: 30, width: 20, height: 20),
            menuSize: CGSize(width: 230, height: 120),
            in: CGRect(x: 0, y: 0, width: 420, height: 560)
        )

        XCTAssertEqual(frame.maxX, 408, accuracy: 0.001)
        XCTAssertEqual(frame.minY, 56, accuracy: 0.001)
    }

    func testPopoverPlacementNeverEscapesTheTopEdge() {
        // The surface is flush with the screen top; a menu anchored high with
        // no room below must clamp inside the bounds, never above them.
        let frame = NotchPopoverPlacement.frame(
            anchor: CGRect(x: 340, y: 40, width: 28, height: 28),
            menuSize: CGSize(width: 230, height: 300),
            in: CGRect(x: 0, y: 0, width: 420, height: 320)
        )

        XCTAssertGreaterThanOrEqual(frame.minY, 12)

        let oversized = NotchPopoverPlacement.frame(
            anchor: CGRect(x: 340, y: 40, width: 28, height: 28),
            menuSize: CGSize(width: 230, height: 600),
            in: CGRect(x: 0, y: 0, width: 420, height: 560)
        )

        XCTAssertGreaterThanOrEqual(oversized.minY, 12)
    }

    func testPopoverPlacementFlipsAboveWhenThereIsNoRoomBelow() {
        let frame = NotchPopoverPlacement.frame(
            anchor: CGRect(x: 190, y: 510, width: 20, height: 20),
            menuSize: CGSize(width: 230, height: 120),
            in: CGRect(x: 0, y: 0, width: 420, height: 560)
        )

        XCTAssertEqual(frame.minY, 384, accuracy: 0.001)
    }

    @MainActor
    func testModalSupersedesMenuAndCoordinatorKeepsOnePresentation() {
        let coordinator = NotchPresentationCoordinator()
        coordinator.present(NotchMenu(title: nil, anchor: .zero, items: []))
        XCTAssertNotNil(coordinator.menu)

        coordinator.present(NotchModal(
            kind: .standard,
            title: "Test",
            message: nil,
            textFieldLabel: nil,
            draft: "",
            primaryTitle: "OK",
            cancelTitle: "Cancel",
            onSubmit: { _ in nil },
            onCancel: {}
        ))

        XCTAssertNil(coordinator.menu)
        XCTAssertTrue(coordinator.hasModal)
    }
}
