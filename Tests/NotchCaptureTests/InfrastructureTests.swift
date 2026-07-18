import AppKit
import CoreGraphics
import SwiftUI
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

final class PanelTransitionPolicyTests: XCTestCase {
    func testHiddenExpandedSurfaceStartsWithExpansionMorph() {
        let policy = PanelTransitionPolicy.resolve(
            from: .dormant,
            to: .expanded,
            wasVisible: false,
            reduceMotion: false
        )

        XCTAssertEqual(policy.kind, .expand)
        XCTAssertEqual(policy.duration, NotchMotion.surfaceExpansionDuration)
        XCTAssertTrue(policy.animatesMorph)
        XCTAssertEqual(policy.opacity, .unchanged)
        XCTAssertEqual(policy.spring, NotchMotion.surfaceExpansion)
    }

    func testHiddenCollapsedSurfaceAlsoMorphsFromTheNotch() {
        let policy = PanelTransitionPolicy.resolve(
            from: .dormant,
            to: .collapsed,
            wasVisible: false,
            reduceMotion: false
        )

        XCTAssertEqual(policy.kind, .expand)
        XCTAssertTrue(policy.animatesMorph)
        XCTAssertEqual(policy.spring, NotchMotion.surfaceExpansion)
        XCTAssertEqual(policy.opacity, .unchanged)
        XCTAssertEqual(policy.fadeDuration, 0)
    }

    func testEveryHiddenVisibleSurfaceUsesTheSharedNotchMorph() {
        for state in PanelState.allCases.filter(\.isVisible) {
            let policy = PanelTransitionPolicy.resolve(
                from: .dormant,
                to: state,
                wasVisible: false,
                reduceMotion: false
            )

            XCTAssertEqual(policy.kind, .expand, "Expected a notch morph for \(state)")
            XCTAssertEqual(policy.spring, NotchMotion.surfaceExpansion)
            XCTAssertEqual(policy.opacity, .unchanged)
        }
    }

    func testExpandedSurfaceContractsToCollapsedPill() {
        let policy = PanelTransitionPolicy.resolve(
            from: .expanded,
            to: .collapsed,
            wasVisible: true,
            reduceMotion: false
        )

        XCTAssertEqual(policy.kind, .contract)
        XCTAssertEqual(policy.duration, NotchMotion.surfaceContractionDuration)
        XCTAssertEqual(policy.spring, NotchMotion.surfaceContraction)
    }

    func testSameSizeContentNavigationDoesNotResizeWindow() {
        let policy = PanelTransitionPolicy.resolve(
            from: .expanded,
            to: .settings,
            wasVisible: true,
            reduceMotion: false
        )

        XCTAssertEqual(policy.kind, .immediate)
        XCTAssertFalse(policy.animatesMorph)
    }

    func testDropTargetDoesNotRestartTheShellMorph() {
        let entering = PanelTransitionPolicy.resolve(
            from: .expanded,
            to: .dropTarget,
            wasVisible: true,
            reduceMotion: false
        )
        let leaving = PanelTransitionPolicy.resolve(
            from: .dropTarget,
            to: .expanded,
            wasVisible: true,
            reduceMotion: false
        )

        XCTAssertEqual(entering.kind, .immediate)
        XCTAssertEqual(leaving.kind, .immediate)
        XCTAssertFalse(entering.animatesMorph)
        XCTAssertFalse(leaving.animatesMorph)
    }

    func testHiddenReducedMotionOpenUsesOnlyTheShortFade() {
        let policy = PanelTransitionPolicy.resolve(
            from: .dormant,
            to: .onboarding,
            wasVisible: false,
            reduceMotion: true
        )

        XCTAssertEqual(policy.kind, .reducedFade)
        XCTAssertFalse(policy.animatesMorph)
        XCTAssertEqual(policy.opacity, .reveal)
        XCTAssertEqual(policy.duration, NotchMotion.reducedMotionDuration)
    }

    func testReducedMotionUsesOpacityWithoutSpatialMorph() {
        let policy = PanelTransitionPolicy.resolve(
            from: .collapsed,
            to: .expanded,
            wasVisible: true,
            reduceMotion: true
        )

        XCTAssertEqual(policy.kind, .reducedFade)
        XCTAssertFalse(policy.animatesMorph)
        XCTAssertEqual(policy.opacity, .unchanged)
        XCTAssertEqual(policy.duration, NotchMotion.reducedMotionDuration)
    }

    func testNotchFlowHandoffMorphsAndFadesBeforeOrderingOut() {
        let policy = PanelTransitionPolicy.resolve(
            from: .expanded,
            to: .dormant,
            wasVisible: true,
            reduceMotion: false
        )

        XCTAssertEqual(policy.kind, .hide)
        XCTAssertEqual(policy.spring, NotchMotion.surfaceHide)
        XCTAssertEqual(policy.opacity, .hide)
        XCTAssertTrue(policy.animatesMorph)
        XCTAssertTrue(policy.ordersOutOnCompletion)
    }

    func testReducedMotionHideUsesOpacityOnly() {
        let policy = PanelTransitionPolicy.resolve(
            from: .expanded,
            to: .dormant,
            wasVisible: true,
            reduceMotion: true
        )

        XCTAssertEqual(policy.kind, .reducedFade)
        XCTAssertFalse(policy.animatesMorph)
        XCTAssertEqual(policy.opacity, .hide)
        XCTAssertEqual(policy.fadeDuration, NotchMotion.reducedMotionDuration)
    }

    func testScreenshotSelectionIsImmediate() {
        let policy = PanelTransitionPolicy.resolve(
            from: .expanded,
            to: .screenshot,
            wasVisible: true,
            reduceMotion: false
        )

        XCTAssertEqual(policy.kind, .immediate)
        XCTAssertFalse(policy.animatesMorph)
        XCTAssertFalse(policy.ordersOutOnCompletion)
    }

    func testExplicitlyNonAnimatedDismissalIsImmediate() {
        let policy = PanelTransitionPolicy.resolve(
            from: .expanded,
            to: .dormant,
            wasVisible: true,
            reduceMotion: false,
            animated: false
        )

        XCTAssertEqual(policy.kind, .immediate)
        XCTAssertFalse(policy.animatesOpacity)
    }

    func testReopeningDuringPendingPhysicalHideRetargetsLivePanel() {
        let policy = PanelTransitionPolicy.resolve(
            from: .dormant,
            to: .expanded,
            wasVisible: true,
            reduceMotion: false
        )

        XCTAssertEqual(policy.kind, .expand)
        XCTAssertEqual(policy.spring, NotchMotion.surfaceExpansion)
        XCTAssertEqual(policy.opacity, .reveal)
    }

    func testDuplicateVisibleTargetDoesNotAnimate() {
        let policy = PanelTransitionPolicy.resolve(
            from: .expanded,
            to: .expanded,
            wasVisible: true,
            reduceMotion: false
        )

        XCTAssertEqual(policy.kind, .immediate)
        XCTAssertFalse(policy.animatesMorph)
    }
}

final class PanelMorphGeometryTests: XCTestCase {
    private let topCenter = CGPoint(x: 756, y: 982)
    private let notchSize = CGSize(width: 152, height: 38)
    private let expandedSize = CGSize(width: 420, height: 560)

    func testInterpolationRemainsTopCenteredAndGrowsMonotonically() {
        let geometry = PanelMorphGeometry(
            topCenter: topCenter,
            sourceSize: notchSize,
            targetSize: expandedSize
        )
        let frames = [0, 0.25, 0.5, 0.75, 1].map {
            geometry.interpolatedFrame(progress: $0)
        }

        for frame in frames {
            XCTAssertEqual(frame.maxY, topCenter.y, accuracy: 0.0001)
            XCTAssertEqual(frame.midX, topCenter.x, accuracy: 0.0001)
        }
        for pair in zip(frames, frames.dropFirst()) {
            XCTAssertGreaterThan(pair.1.width, pair.0.width)
            XCTAssertGreaterThan(pair.1.height, pair.0.height)
        }
        XCTAssertEqual(frames.first, geometry.sourceFrame)
        XCTAssertEqual(frames.last, geometry.targetFrame)
    }

    func testReverseMorphRetracesTheOpeningPath() {
        let opening = PanelMorphGeometry(
            topCenter: topCenter,
            sourceSize: notchSize,
            targetSize: expandedSize
        )
        let closing = PanelMorphGeometry(
            topCenter: topCenter,
            sourceSize: expandedSize,
            targetSize: notchSize
        )

        for progress in stride(from: CGFloat(0), through: 1, by: 0.1) {
            let openingFrame = opening.interpolatedFrame(progress: progress)
            let closingFrame = closing.interpolatedFrame(progress: 1 - progress)
            XCTAssertEqual(openingFrame.minX, closingFrame.minX, accuracy: 0.0001)
            XCTAssertEqual(openingFrame.minY, closingFrame.minY, accuracy: 0.0001)
            XCTAssertEqual(openingFrame.width, closingFrame.width, accuracy: 0.0001)
            XCTAssertEqual(openingFrame.height, closingFrame.height, accuracy: 0.0001)
        }
    }

    func testCanvasReservesTheLargestSurfaceAndShadowApron() {
        let geometry = PanelMorphGeometry(
            topCenter: topCenter,
            sourceSize: expandedSize,
            targetSize: CGSize(width: 178, height: 34)
        )
        let frame = geometry.panelCanvasFrame(horizontalApron: 64, bottomApron: 80)

        XCTAssertEqual(frame.size, CGSize(width: 548, height: 640))
        XCTAssertEqual(frame.midX, topCenter.x)
        XCTAssertEqual(frame.maxY, topCenter.y)
    }

    func testNotchAnchorUsesHardwareGeometryAndExternalFallback() {
        let hardware = makeDisplayGeometry(
            notchRect: CGRect(x: 680, y: 944, width: 152, height: 38),
            safeTop: 38
        )
        let external = makeDisplayGeometry(notchRect: nil, safeTop: 0)

        XCTAssertEqual(
            PanelMorphGeometry.notchAnchorSize(for: hardware),
            CGSize(width: 152, height: 38)
        )
        XCTAssertEqual(
            PanelMorphGeometry.notchAnchorSize(for: external),
            PanelMorphGeometry.virtualNotchSize
        )

        let collapsedAnchor = PanelMorphGeometry.concealedAnchorSize(
            for: hardware,
            targetSize: CGSize(width: 178, height: 34)
        )
        XCTAssertEqual(collapsedAnchor, CGSize(width: 152, height: 34))
        XCTAssertLessThanOrEqual(collapsedAnchor.width, 178)
        XCTAssertLessThanOrEqual(collapsedAnchor.height, 34)

        let collapsedMorph = PanelMorphGeometry(
            topCenter: topCenter,
            sourceSize: collapsedAnchor,
            targetSize: CGSize(width: 178, height: 34)
        )
        let collapsedFrames = [0, 0.5, 1].map {
            collapsedMorph.interpolatedFrame(progress: $0)
        }
        for pair in zip(collapsedFrames, collapsedFrames.dropFirst()) {
            XCTAssertGreaterThanOrEqual(pair.1.width, pair.0.width)
            XCTAssertGreaterThanOrEqual(pair.1.height, pair.0.height)
        }
    }

    func testInterpolationClampsOutOfRangeProgress() {
        let geometry = PanelMorphGeometry(
            topCenter: topCenter,
            sourceSize: notchSize,
            targetSize: expandedSize
        )

        XCTAssertEqual(geometry.interpolatedFrame(progress: -1), geometry.sourceFrame)
        XCTAssertEqual(geometry.interpolatedFrame(progress: 2), geometry.targetFrame)
    }

    private func makeDisplayGeometry(notchRect: CGRect?, safeTop: CGFloat) -> NotchGeometry {
        let screenFrame = CGRect(x: 0, y: 0, width: 1_512, height: 982)
        return NotchGeometry(
            displayID: 42,
            screenFrame: screenFrame,
            visibleFrame: screenFrame.insetBy(dx: 0, dy: 24),
            safeAreaInsets: NSEdgeInsets(top: safeTop, left: 0, bottom: 0, right: 0),
            notchRect: notchRect
        )
    }
}

@MainActor
final class PanelMorphCoordinatorTests: XCTestCase {
    func testStaleActivationAndCompletionCannotReplaceTheCurrentGeneration() {
        let coordinator = PanelMorphCoordinator()
        let first = makeRequest(generation: 1)
        let second = makeRequest(generation: 2)

        coordinator.prepare(first)
        coordinator.begin(second)
        coordinator.activate(generation: 1)
        coordinator.settle(generation: 1)

        XCTAssertEqual(coordinator.request?.generation, 2)
        XCTAssertEqual(coordinator.request?.phase, .active)

        coordinator.settle(generation: 2)
        XCTAssertEqual(coordinator.request?.phase, .settled)

        coordinator.cancel()
        XCTAssertNil(coordinator.request)
    }

    func testRequestDurationIncludesAnyExplicitShellDelay() {
        let request = makeRequest(generation: 1, shellDelay: 0.04)

        XCTAssertEqual(request.morphDuration, 0.48)
        XCTAssertEqual(request.totalDuration, 0.52)
    }

    private func makeRequest(
        generation: Int,
        shellDelay: TimeInterval = 0
    ) -> PanelMorphRequest {
        PanelMorphRequest(
            generation: generation,
            phase: .active,
            geometry: PanelMorphGeometry(
                topCenter: CGPoint(x: 756, y: 982),
                sourceSize: CGSize(width: 420, height: 560),
                targetSize: CGSize(width: 178, height: 34)
            ),
            targetState: .collapsed,
            kind: .contract,
            spring: NotchMotion.surfaceContraction,
            fadeDuration: 0,
            shellDelay: shellDelay,
            contentDelay: NotchMotion.surfaceContentDelay,
            reduceMotion: false,
            wasVisible: true
        )
    }
}

final class SurfaceChromeMetricsTests: XCTestCase {
    func testVisibleSurfaceGeometryMatchesThePersistentShell() throws {
        XCTAssertEqual(
            try XCTUnwrap(SurfaceChromeMetrics.resolve(for: .collapsed)).size,
            CGSize(width: 178, height: 34)
        )
        XCTAssertEqual(
            try XCTUnwrap(SurfaceChromeMetrics.resolve(for: .confirmation)).size,
            CGSize(width: 280, height: 56)
        )
        XCTAssertEqual(
            try XCTUnwrap(SurfaceChromeMetrics.resolve(for: .expanded)).size,
            CGSize(width: 420, height: 560)
        )
        XCTAssertEqual(
            try XCTUnwrap(SurfaceChromeMetrics.resolve(for: .onboarding)).size,
            CGSize(width: 420, height: 500)
        )
        XCTAssertEqual(
            try XCTUnwrap(SurfaceChromeMetrics.resolve(for: .settings)).size,
            CGSize(width: 420, height: 560)
        )
    }

    func testHiddenStatesDoNotReplaceTheLastVisibleChrome() {
        XCTAssertNil(SurfaceChromeMetrics.resolve(for: .dormant))
        XCTAssertNil(SurfaceChromeMetrics.resolve(for: .screenshot))
    }

    func testCollapsedChromeDropsTheOuterShadowAtTheTightWindowBoundary() throws {
        let collapsed = try XCTUnwrap(SurfaceChromeMetrics.resolve(for: .collapsed))
        let expanded = try XCTUnwrap(SurfaceChromeMetrics.resolve(for: .expanded))

        XCTAssertEqual(collapsed.shadowOpacity, 0)
        XCTAssertEqual(collapsed.shadowRadius, 0)
        XCTAssertEqual(collapsed.shadowY, 0)
        XCTAssertGreaterThan(expanded.shadowOpacity, 0)
        XCTAssertGreaterThan(expanded.shadowRadius, 0)
    }

    func testPreparedChromeUsesTheConcealedNotchSourceWithoutAShadow() throws {
        let expanded = try XCTUnwrap(SurfaceChromeMetrics.resolve(for: .expanded))
        let anchored = expanded.anchored(at: CGSize(width: 152, height: 38))

        XCTAssertEqual(anchored.size, CGSize(width: 152, height: 38))
        XCTAssertEqual(anchored.shadowOpacity, 0)
        XCTAssertEqual(anchored.shadowY, 0)
        XCTAssertLessThanOrEqual(anchored.bottomRadius, 19)
    }
}

final class PanelShadowApronTests: XCTestCase {
    func testCollapsedSurfaceUsesNoShadowApron() {
        let apron = PanelShadowApron.resolve(for: .collapsed)

        XCTAssertEqual(apron, .none)
        XCTAssertEqual(
            apron.applying(to: CGSize(width: 178, height: 34)),
            CGSize(width: 178, height: 34)
        )
        XCTAssertEqual(
            apron.applying(to: CGSize(width: 180, height: 34)),
            CGSize(width: 180, height: 34)
        )
    }

    func testVisibleOpenSurfacesRetainTheStandardShadowCanvas() {
        let openStates: [PanelState] = [
            .confirmation,
            .expanded,
            .dropTarget,
            .onboarding,
            .settings,
        ]

        for state in openStates {
            XCTAssertEqual(PanelShadowApron.resolve(for: state), .standard)
        }
        XCTAssertEqual(
            PanelShadowApron.standard.applying(to: CGSize(width: 420, height: 560)),
            CGSize(width: 548, height: 640)
        )
    }
}

final class NotchMotionTokenTests: XCTestCase {
    func testLiquidSurfaceProfilesAreUnderdamped() {
        let profiles: [(NotchSpringProfile, TimeInterval, Double)] = [
            (NotchMotion.surfaceExpansion, 0.56, 0.16),
            (NotchMotion.surfaceContraction, 0.48, 0.12),
            (NotchMotion.surfaceHide, 0.44, 0.09),
            (NotchMotion.surfaceContent, 0.38, 0.07),
        ]

        for (profile, duration, bounce) in profiles {
            XCTAssertEqual(profile.perceptualDuration, duration)
            XCTAssertEqual(profile.bounce, bounce)
            XCTAssertGreaterThan(profile.bounce, 0)
        }
    }

    func testRestrainedInteractionProfilesKeepTheirPerceptualDurations() {
        let profiles: [(NotchSpringProfile, TimeInterval)] = [
            (NotchMotion.contentMorph, 0.30),
            (NotchMotion.selection, 0.22),
            (NotchMotion.reorderDisplacement, 0.30),
            (NotchMotion.dragLift, 0.20),
            (NotchMotion.dragLanding, 0.34),
            (NotchMotion.onboardingSpring, 0.36),
            (NotchMotion.confirmationSpring, 0.32),
            (NotchMotion.completionSpring, 0.16),
        ]

        for (profile, duration) in profiles {
            XCTAssertEqual(profile.perceptualDuration, duration)
            XCTAssertEqual(profile.bounce, 0)
        }
    }

    func testFastEaseOutDurationsRemainResponsive() {
        XCTAssertEqual(NotchMotion.hoverDuration, 0.08)
        XCTAssertEqual(NotchMotion.controlPressDuration, 0.12)
        XCTAssertEqual(NotchMotion.insertionDuration, 0.18)
        XCTAssertEqual(NotchMotion.removalDuration, 0.14)
        XCTAssertEqual(NotchMotion.reducedMotionDuration, 0.12)
        XCTAssertEqual(NotchMotion.surfaceContentDelay, 0.018)
        XCTAssertEqual(NotchMotion.surfaceContentOffset, 6)
        XCTAssertEqual(NotchMotion.expandedLedgerDelay, 0.10)
        XCTAssertEqual(NotchMotion.expandedComposerDelay, 0.24)
        XCTAssertEqual(NotchMotion.expandedElementRevealDuration, 0.24)
        XCTAssertLessThan(
            NotchMotion.expandedLedgerDelay,
            NotchMotion.expandedComposerDelay
        )
        XCTAssertEqual(NotchMotion.completionRevealDuration, 0.30)
        XCTAssertEqual(NotchMotion.completionRetractDuration, 0.16)
        XCTAssertEqual(NotchMotion.completionReopenDuration, 0.16)
        XCTAssertEqual(NotchMotion.completionExitDuration, 0.16)
        XCTAssertEqual(NotchMotion.completionSpring.bounce, 0)
        XCTAssertLessThanOrEqual(NotchMotion.completionExitDuration, 0.25)
    }
}

final class ExpandedSurfaceRevealPlanTests: XCTestCase {
    func testExpansionRevealsLedgerBeforeComposer() throws {
        let request = makeRequest(phase: .active, kind: .expand, targetState: .expanded)
        let plan = try XCTUnwrap(
            ExpandedSurfaceRevealPlan.resolve(for: request, reduceMotion: false)
        )

        XCTAssertEqual(plan.generation, request.generation)
        XCTAssertEqual(plan.ledgerDelay, NotchMotion.expandedLedgerDelay)
        XCTAssertEqual(plan.composerDelay, NotchMotion.expandedComposerDelay)
        XCTAssertGreaterThan(plan.composerDelay, plan.ledgerDelay)
    }

    func testPreparedReducedAndNonExpansionStatesDoNotStartAStagger() {
        XCTAssertNil(ExpandedSurfaceRevealPlan.resolve(
            for: makeRequest(phase: .prepared, kind: .expand, targetState: .expanded),
            reduceMotion: false
        ))
        XCTAssertNil(ExpandedSurfaceRevealPlan.resolve(
            for: makeRequest(phase: .active, kind: .expand, targetState: .expanded),
            reduceMotion: true
        ))
        XCTAssertNil(ExpandedSurfaceRevealPlan.resolve(
            for: makeRequest(phase: .active, kind: .contract, targetState: .collapsed),
            reduceMotion: false
        ))
    }

    private func makeRequest(
        phase: PanelMorphRequest.Phase,
        kind: PanelTransitionPolicy.Kind,
        targetState: PanelState
    ) -> PanelMorphRequest {
        PanelMorphRequest(
            generation: 7,
            phase: phase,
            geometry: PanelMorphGeometry(
                topCenter: CGPoint(x: 756, y: 982),
                sourceSize: CGSize(width: 178, height: 34),
                targetSize: CGSize(width: 420, height: 560)
            ),
            targetState: targetState,
            kind: kind,
            spring: NotchMotion.surfaceExpansion,
            fadeDuration: 0,
            shellDelay: 0,
            contentDelay: NotchMotion.surfaceContentDelay,
            reduceMotion: false,
            wasVisible: true
        )
    }
}

final class LedgerCompletionRevealGeometryTests: XCTestCase {
    private let rowRect = CGRect(x: 0, y: 0, width: 420, height: 56)

    func testRevealStartsAtCheckboxAndBloomsAroundItsOrigin() {
        let initial = LedgerCompletionRevealGeometry.revealFrame(
            in: rowRect,
            progress: 0
        )
        XCTAssertEqual(initial.midX, LedgerCompletionRevealGeometry.originX)
        XCTAssertEqual(initial.midY, rowRect.midY)
        XCTAssertEqual(initial.width, 0)
        XCTAssertEqual(initial.height, 0)

        let bloomProgress = 28 / rowRect.width
        let bloom = LedgerCompletionRevealGeometry.revealFrame(
            in: rowRect,
            progress: bloomProgress
        )
        XCTAssertEqual(bloom.midX, LedgerCompletionRevealGeometry.originX, accuracy: 0.001)
        XCTAssertEqual(bloom.midY, rowRect.midY, accuracy: 0.001)
        XCTAssertEqual(bloom.width, bloom.height, accuracy: 0.001)
    }

    func testRevealWidthGrowsMonotonicallyAndFinishesAcrossTheRow() {
        let frames = stride(from: CGFloat.zero, through: 1, by: 0.1).map {
            LedgerCompletionRevealGeometry.revealFrame(in: rowRect, progress: $0)
        }

        for pair in zip(frames, frames.dropFirst()) {
            XCTAssertLessThanOrEqual(pair.0.width, pair.1.width)
        }
        XCTAssertEqual(frames.last, rowRect)
    }

    func testRevealClampsProgressAndCoversEverySupportedRowHeight() {
        XCTAssertEqual(
            LedgerCompletionRevealGeometry.revealFrame(in: rowRect, progress: -1).width,
            0
        )
        XCTAssertEqual(
            LedgerCompletionRevealGeometry.revealFrame(in: rowRect, progress: 2),
            rowRect
        )

        for height: CGFloat in [56, 64, 66] {
            let rect = CGRect(x: 0, y: 0, width: 420, height: height)
            XCTAssertEqual(
                LedgerCompletionRevealGeometry.revealFrame(in: rect, progress: 1),
                rect
            )
        }
    }

    func testCompletedRevealFinishesWithRectangularCorners() {
        let completedFrame = LedgerCompletionRevealGeometry.revealFrame(
            in: rowRect,
            progress: 1
        )

        XCTAssertEqual(
            LedgerCompletionRevealGeometry.cornerRadius(
                for: completedFrame,
                progress: 1
            ),
            0
        )
    }
}

@MainActor
final class PanelChromeTests: XCTestCase {
    func testRoundedShellDoesNotReceiveARectangularWindowShadow() {
        let controller = PanelController(automaticDismissalEnabled: false) { _ in
            AnyView(EmptyView())
        }

        XCTAssertFalse(controller.panel.hasShadow)
    }

    func testPanelControllerOwnsWindowSizingInsteadOfHostedContent() throws {
        let controller = PanelController(automaticDismissalEnabled: false) { _ in
            AnyView(Color.clear.frame(width: 420, height: 560))
        }
        let hostingView = try XCTUnwrap(
            controller.panel.contentView as? NSHostingView<AnyView>
        )

        hostingView.layoutSubtreeIfNeeded()

        XCTAssertTrue(hostingView.sizingOptions.isEmpty)
        XCTAssertEqual(controller.panel.contentMinSize, .zero)
    }
}

final class PanelWindowInteractionPolicyTests: XCTestCase {
    func testCollapsedContractionSuspendsHitTestingUntilTheIdleFrameSettles() {
        let transition = PanelTransitionPolicy.resolve(
            from: .expanded,
            to: .collapsed,
            wasVisible: true,
            reduceMotion: false
        )
        let expandedFrame = CGRect(x: 482, y: 342, width: 548, height: 640)
        let collapsedFrame = CGRect(x: 666, y: 948, width: 180, height: 34)

        XCTAssertTrue(PanelWindowInteractionPolicy.suspendsHitTesting(
            during: transition,
            targetState: .collapsed,
            wasVisible: true
        ))
        XCTAssertFalse(PanelWindowInteractionPolicy.canRestoreHitTesting(
            actualFrame: expandedFrame,
            targetFrame: collapsedFrame
        ))
        XCTAssertTrue(PanelWindowInteractionPolicy.canRestoreHitTesting(
            actualFrame: collapsedFrame,
            targetFrame: collapsedFrame
        ))
    }

    func testExpansionKeepsTheLivePanelInteractive() {
        let transition = PanelTransitionPolicy.resolve(
            from: .collapsed,
            to: .expanded,
            wasVisible: true,
            reduceMotion: false
        )

        XCTAssertFalse(PanelWindowInteractionPolicy.suspendsHitTesting(
            during: transition,
            targetState: .expanded,
            wasVisible: true
        ))
    }

    func testReducedMotionContractionSuspendsHitTestingUntilTheIdleFrameSettles() {
        let transition = PanelTransitionPolicy.resolve(
            from: .expanded,
            to: .collapsed,
            wasVisible: true,
            reduceMotion: true
        )

        XCTAssertEqual(transition.kind, .reducedFade)
        XCTAssertTrue(PanelWindowInteractionPolicy.suspendsHitTesting(
            during: transition,
            targetState: .collapsed,
            wasVisible: true
        ))
    }

    func testOpeningDirectlyIntoCollapsedStateDoesNotSuspendHitTesting() {
        let transition = PanelTransitionPolicy.resolve(
            from: .dormant,
            to: .collapsed,
            wasVisible: false,
            reduceMotion: true
        )

        XCTAssertFalse(PanelWindowInteractionPolicy.suspendsHitTesting(
            during: transition,
            targetState: .collapsed,
            wasVisible: false
        ))
    }
}

@MainActor
final class PanelDismissalEventPolicyTests: XCTestCase {
    func testLocalMonitorLeavesMouseEventsToAppOwnedDialogs() {
        XCTAssertTrue(PanelDismissalEventPolicy.localEventMask.contains(.keyDown))
        XCTAssertFalse(PanelDismissalEventPolicy.localEventMask.contains(.leftMouseDown))
        XCTAssertFalse(PanelDismissalEventPolicy.localEventMask.contains(.rightMouseDown))
    }

    func testEscapeDismissesTheNotchPanel() {
        let panel = NSPanel()

        XCTAssertTrue(PanelDismissalEventPolicy.shouldDismissForEscape(
            eventWindow: panel,
            panel: panel
        ))
    }

    func testEscapeIsPassedToAnAppOwnedDialog() {
        let panel = NSPanel()
        let dialog = NSWindow()

        XCTAssertFalse(PanelDismissalEventPolicy.shouldDismissForEscape(
            eventWindow: dialog,
            panel: panel
        ))
    }

    func testExternalClickDismissesWhenThePanelIsTheOnlyVisibleWindow() {
        XCTAssertTrue(PanelDismissalEventPolicy.shouldDismissForExternalClick(
            hasVisibleAuxiliaryWindow: false
        ))
    }

    func testExternalClickDoesNotDestroyAnActiveDialog() {
        XCTAssertFalse(PanelDismissalEventPolicy.shouldDismissForExternalClick(
            hasVisibleAuxiliaryWindow: true
        ))
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

        let panel = NotchPanel()
        var interceptedImagePaste = false
        panel.onComposerImagePaste = { _ in
            interceptedImagePaste = true
            return true
        }
        XCTAssertTrue(panel.performKeyEquivalent(with: commandV))
        XCTAssertTrue(interceptedImagePaste)
    }

    func testNotchPanelClassifiesUnmodifiedLedgerRowCommands() throws {
        let returnKey = try XCTUnwrap(makeKeyEvent(characters: "\r", keyCode: 36))
        let keypadEnter = try XCTUnwrap(makeKeyEvent(characters: "\r", keyCode: 76))
        let space = try XCTUnwrap(makeKeyEvent(characters: " ", keyCode: 49))
        let delete = try XCTUnwrap(makeKeyEvent(characters: "\u{8}", keyCode: 51))
        let forwardDelete = try XCTUnwrap(makeKeyEvent(characters: "\u{7F}", keyCode: 117))

        XCTAssertEqual(NotchPanel.ledgerRowKeyboardCommand(for: returnKey), .toggleCompletion)
        XCTAssertEqual(NotchPanel.ledgerRowKeyboardCommand(for: keypadEnter), .toggleCompletion)
        XCTAssertEqual(NotchPanel.ledgerRowKeyboardCommand(for: space), .toggleCompletion)
        XCTAssertEqual(NotchPanel.ledgerRowKeyboardCommand(for: delete), .moveToTrash)
        XCTAssertEqual(NotchPanel.ledgerRowKeyboardCommand(for: forwardDelete), .moveToTrash)
    }

    func testNotchPanelLeavesModifiedAndRepeatedLedgerRowKeysToTheResponderChain() throws {
        let commandSpace = try XCTUnwrap(makeKeyEvent(
            characters: " ",
            modifierFlags: .command,
            keyCode: 49
        ))
        let repeatedSpace = try XCTUnwrap(makeKeyEvent(
            characters: " ",
            isARepeat: true,
            keyCode: 49
        ))
        let otherKey = try XCTUnwrap(makeKeyEvent(characters: "a", keyCode: 0))

        XCTAssertNil(NotchPanel.ledgerRowKeyboardCommand(for: commandSpace))
        XCTAssertNil(NotchPanel.ledgerRowKeyboardCommand(for: repeatedSpace))
        XCTAssertNil(NotchPanel.ledgerRowKeyboardCommand(for: otherKey))
    }

    private func makeKeyEvent(
        characters: String,
        modifierFlags: NSEvent.ModifierFlags = [],
        isARepeat: Bool = false,
        keyCode: UInt16
    ) -> NSEvent? {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifierFlags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: isARepeat,
            keyCode: keyCode
        )
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

    func testCollapsedAndExpandedFramesShareTheSameTopAnchor() {
        let geometry = makeGeometry(
            screenFrame: CGRect(x: 0, y: 0, width: 1_512, height: 982),
            notchRect: CGRect(x: 680, y: 944, width: 152, height: 38)
        )

        let collapsed = geometry.panelFrame(for: CGSize(width: 176, height: 44))
        let expanded = geometry.panelFrame(for: CGSize(width: 420, height: 560))

        XCTAssertEqual(collapsed.maxY, expanded.maxY)
        XCTAssertEqual(collapsed.midX, expanded.midX)
        XCTAssertEqual(collapsed.maxY, geometry.screenFrame.maxY)
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
