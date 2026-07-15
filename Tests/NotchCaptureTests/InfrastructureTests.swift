import AppKit
import CoreGraphics
import XCTest
@testable import NotchCapture

final class PanelStateTests: XCTestCase {
    func testVisibilityMatchesWindowOwnership() {
        XCTAssertFalse(PanelState.dormant.isVisible)
        XCTAssertFalse(PanelState.screenshot.isVisible)

        for state in PanelState.allCases.filter({ $0 != .dormant && $0 != .screenshot }) {
            XCTAssertTrue(state.isVisible, "Expected \(state) to own a visible panel")
        }
    }

    func testOnlyEditableSurfacesAcceptKeyboardInput() {
        let editableStates: Set<PanelState> = [.expanded, .dropTarget, .onboarding, .settings]

        for state in PanelState.allCases {
            XCTAssertEqual(
                state.acceptsKeyboardInput,
                editableStates.contains(state),
                "Unexpected keyboard behavior for \(state)"
            )
        }
    }

    func testExplicitSessionsExcludePassiveStates() {
        let passiveStates: Set<PanelState> = [.dormant, .collapsed, .screenshot]

        for state in PanelState.allCases {
            XCTAssertEqual(
                state.isExplicitSession,
                !passiveStates.contains(state),
                "Unexpected session behavior for \(state)"
            )
        }
    }
}

@MainActor
final class ApplicationMenuTests: XCTestCase {
    func testEditMenuProvidesStandardPasteResponderCommand() throws {
        let menu = ApplicationMenuFactory.makeMainMenu()
        let editMenu = try XCTUnwrap(menu.items.first(where: { $0.submenu?.title == "Edit" })?.submenu)
        let paste = try XCTUnwrap(editMenu.items.first(where: { $0.title == "Paste" }))

        XCTAssertEqual(paste.action, #selector(NSText.paste(_:)))
        XCTAssertEqual(paste.keyEquivalent, "v")
        XCTAssertTrue(paste.keyEquivalentModifierMask.contains(.command))
        XCTAssertNil(paste.target, "A nil target routes Paste through the active field editor responder chain")
    }

    func testNotchPanelRoutesCommandVDirectlyToPasteResponder() throws {
        let commandV = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "v",
            charactersIgnoringModifiers: "v",
            isARepeat: false,
            keyCode: 9
        ))

        XCTAssertEqual(NotchPanel.editingAction(for: commandV), #selector(NSText.paste(_:)))
    }
}

@MainActor
final class LedgerScrollAppearanceTests: XCTestCase {
    func testLedgerScrollIndicatorsAreFullyHidden() {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.scrollerStyle = .legacy

        LedgerScrollAppearance.hideIndicators(in: scrollView)

        XCTAssertFalse(scrollView.hasVerticalScroller)
        XCTAssertFalse(scrollView.hasHorizontalScroller)
        XCTAssertTrue(scrollView.autohidesScrollers)
        XCTAssertEqual(scrollView.scrollerStyle, .overlay)
    }
}

final class NotchGeometryTests: XCTestCase {
    func testPanelHugsTopEdgeAndCentersOnHardwareNotch() {
        let geometry = makeGeometry(
            screenFrame: CGRect(x: 0, y: 0, width: 1_512, height: 982),
            notchRect: CGRect(x: 680, y: 944, width: 152, height: 38)
        )

        let frame = geometry.panelFrame(for: CGSize(width: 420, height: 560))

        XCTAssertEqual(frame, CGRect(x: 546, y: 422, width: 420, height: 560))
        XCTAssertEqual(frame.maxY, geometry.screenFrame.maxY)
        XCTAssertEqual(frame.midX, geometry.notchRect?.midX)
    }

    func testExternalDisplayUsesDisplayCenter() {
        let geometry = makeGeometry(
            screenFrame: CGRect(x: -1_920, y: 0, width: 1_920, height: 1_080),
            notchRect: nil,
            safeTop: 0
        )

        let frame = geometry.panelFrame(for: CGSize(width: 176, height: 36))

        XCTAssertEqual(frame, CGRect(x: -1_048, y: 1_044, width: 176, height: 36))
        XCTAssertEqual(frame.midX, geometry.screenFrame.midX)
    }

    func testPanelIsClampedInsideHorizontalDisplayBounds() {
        let geometry = makeGeometry(
            screenFrame: CGRect(x: 100, y: 50, width: 1_000, height: 700),
            notchRect: CGRect(x: 100, y: 712, width: 80, height: 38)
        )

        let frame = geometry.panelFrame(for: CGSize(width: 420, height: 300))

        XCTAssertEqual(frame.minX, geometry.screenFrame.minX)
        XCTAssertEqual(frame.maxY, geometry.screenFrame.maxY)
    }

    func testHardwareNotchRequiresGeometryAndSafeTopInset() {
        XCTAssertTrue(makeGeometry(notchRect: CGRect(x: 700, y: 944, width: 112, height: 38)).hasHardwareNotch)
        XCTAssertFalse(makeGeometry(notchRect: nil).hasHardwareNotch)
        XCTAssertFalse(
            makeGeometry(
                notchRect: CGRect(x: 700, y: 944, width: 112, height: 38),
                safeTop: 0
            ).hasHardwareNotch
        )
    }

    private func makeGeometry(
        screenFrame: CGRect = CGRect(x: 0, y: 0, width: 1_512, height: 982),
        notchRect: CGRect?,
        safeTop: CGFloat = 38
    ) -> NotchGeometry {
        NotchGeometry(
            displayID: 42,
            screenFrame: screenFrame,
            visibleFrame: screenFrame.insetBy(dx: 0, dy: 24),
            safeAreaInsets: NSEdgeInsets(top: safeTop, left: 0, bottom: 0, right: 0),
            notchRect: notchRect
        )
    }
}

final class SurfaceOccupancySnapshotTests: XCTestCase {
    func testMappedOccupancyIsDisplaySpecific() {
        let snapshot = SurfaceOccupancySnapshot(
            occupiedDisplayIDs: [7],
            detectedBundleIdentifiers: [SurfaceOccupancyService.notchFlowBundleIdentifier]
        )

        XCTAssertTrue(snapshot.hasKnownUtilityRunning)
        XCTAssertTrue(snapshot.isOccupied(displayID: 7))
        XCTAssertFalse(snapshot.isOccupied(displayID: 8))
        XCTAssertFalse(snapshot.usesConservativeFallback)
    }

    func testConservativeFallbackTreatsEveryDisplayAsOccupied() {
        let snapshot = SurfaceOccupancySnapshot(
            detectedBundleIdentifiers: [SurfaceOccupancyService.notchFlowBundleIdentifier],
            usesConservativeFallback: true
        )

        XCTAssertTrue(snapshot.isOccupied(displayID: 1))
        XCTAssertTrue(snapshot.isOccupied(displayID: 999))
    }

    func testEmptySnapshotHasNoDetectedUtilityOrOccupancy() {
        let snapshot = SurfaceOccupancySnapshot()

        XCTAssertFalse(snapshot.hasKnownUtilityRunning)
        XCTAssertFalse(snapshot.isOccupied(displayID: 1))
        XCTAssertTrue(snapshot.occupiedDisplayIDs.isEmpty)
    }

    @MainActor
    func testServiceWithNoKnownBundleIdentifiersPublishesEmptySnapshot() {
        let service = SurfaceOccupancyService(
            knownBundleIdentifiers: [],
            refreshInterval: 0,
            windowInfoProvider: { [] }
        )

        service.refresh()

        XCTAssertEqual(service.snapshot, SurfaceOccupancySnapshot())
    }
}
