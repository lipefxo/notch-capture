import AppKit
import CoreGraphics
import SwiftUI
import XCTest
@testable import NotchCapture

final class PanelStateTests: XCTestCase {
    func testVisibilityMatchesWindowOwnership() {
        XCTAssertFalse(PanelState.dormant.isVisible)

        for state in PanelState.allCases.filter({ $0 != .dormant }) {
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
        let passiveStates: Set<PanelState> = [.dormant, .collapsed, .collapsedActivity]

        for state in PanelState.allCases {
            XCTAssertEqual(
                state.isExplicitSession,
                !passiveStates.contains(state),
                "Unexpected session behavior for \(state)"
            )
        }
    }
}

final class IdlePillVisibilityPolicyTests: XCTestCase {
    func testIdlePillStaysVisibleByDefaultAndOnHardwareNotchDisplays() {
        XCTAssertFalse(
            IdlePillVisibilityPolicy.shouldHide(
                autoHideExternalPill: false,
                pointerHasHardwareNotch: false
            )
        )
        XCTAssertFalse(
            IdlePillVisibilityPolicy.shouldHide(
                autoHideExternalPill: true,
                pointerHasHardwareNotch: true
            )
        )
    }

    func testIdlePillHidesOnlyOnKnownExternalDisplays() {
        XCTAssertTrue(
            IdlePillVisibilityPolicy.shouldHide(
                autoHideExternalPill: true,
                pointerHasHardwareNotch: false
            )
        )
        XCTAssertFalse(
            IdlePillVisibilityPolicy.shouldHide(
                autoHideExternalPill: true,
                pointerHasHardwareNotch: nil
            )
        )
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

    func testPassiveSurfaceHideMorphsAndFadesBeforeOrderingOut() {
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

    func testForegroundCanvasReservesOnlyTheLargestSurface() {
        let geometry = PanelMorphGeometry(
            topCenter: topCenter,
            sourceSize: expandedSize,
            targetSize: CGSize(width: 178, height: 34)
        )
        let frame = geometry.canvasFrame

        XCTAssertEqual(frame.size, expandedSize)
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
        // Chrome sizes derive from PanelState.nominalSize; these literals pin
        // the single table against accidental changes.
        XCTAssertEqual(
            try XCTUnwrap(SurfaceChromeMetrics.resolve(for: .collapsed)).size,
            CGSize(width: 198, height: 34)
        )
        XCTAssertEqual(
            try XCTUnwrap(SurfaceChromeMetrics.resolve(for: .confirmation)).size,
            CGSize(width: 300, height: 56)
        )
        XCTAssertEqual(
            try XCTUnwrap(SurfaceChromeMetrics.resolve(for: .expanded)).size,
            CGSize(width: 440, height: 560)
        )
        XCTAssertEqual(
            try XCTUnwrap(SurfaceChromeMetrics.resolve(for: .onboarding)).size,
            CGSize(width: 440, height: 500)
        )
        XCTAssertEqual(
            try XCTUnwrap(SurfaceChromeMetrics.resolve(for: .settings)).size,
            CGSize(width: 440, height: 560)
        )
    }

    func testHiddenStatesDoNotReplaceTheLastVisibleChrome() {
        XCTAssertNil(SurfaceChromeMetrics.resolve(for: .dormant))
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

    func testVisibleOpenSurfacesUseTheStandardShadowCanvasWithoutExpandingTheSurface() {
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
            PanelState.expanded.nominalSize,
            CGSize(width: 440, height: 560)
        )
        XCTAssertEqual(
            PanelShadowApron.standard.applying(to: PanelState.expanded.nominalSize),
            CGSize(width: 568, height: 640)
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
            (NotchMotion.toggleThumb, 0.26, 0.16),
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
            (NotchMotion.onboardingSpring, 0.28),
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
        XCTAssertEqual(NotchMotion.toggleTrackDuration, 0.16)
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
        XCTAssertEqual(NotchMotion.completionRevealDuration, 0.40)
        XCTAssertEqual(NotchMotion.completionRetractDuration, 0.16)
        XCTAssertEqual(NotchMotion.completionReopenDuration, 0.16)
        XCTAssertEqual(NotchMotion.completionExitDuration, 0.22)
        XCTAssertEqual(NotchMotion.completionSpring.bounce, 0)
        XCTAssertLessThanOrEqual(NotchMotion.completionExitDuration, 0.25)
        XCTAssertEqual(NotchMotion.completionWashDelay, 0.04)
        XCTAssertEqual(NotchMotion.completionHoldDuration, 0.60)
    }

    func testCompletionCheckPopIsPlayfulButBrief() {
        XCTAssertEqual(NotchMotion.completionCheckPop.perceptualDuration, 0.40)
        XCTAssertEqual(NotchMotion.completionCheckPop.bounce, 0.30)
        XCTAssertGreaterThan(NotchMotion.completionCheckPop.bounce, 0)
    }

    func testCompletionHoldOutlastsTheWashReveal() {
        XCTAssertLessThan(
            NotchMotion.completionWashDelay + NotchMotion.completionRevealDuration,
            NotchMotion.completionHoldDuration
        )
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

final class LedgerCompletionLayerLifecycleTests: XCTestCase {
    func testInitialVisibilityMatchesCompletionState() {
        let incomplete = LedgerCompletionLayerLifecycle(isCompleted: false)
        XCTAssertEqual(incomplete.progress, 0)
        XCTAssertFalse(incomplete.showsLayers)

        let completed = LedgerCompletionLayerLifecycle(isCompleted: true)
        XCTAssertEqual(completed.progress, 1)
        XCTAssertTrue(completed.showsLayers)
    }

    func testRetractionKeepsLayersUntilCleanupFinishes() {
        var lifecycle = LedgerCompletionLayerLifecycle(isCompleted: true)
        XCTAssertTrue(lifecycle.beginTransition(to: false))
        XCTAssertEqual(lifecycle.progress, 0)
        XCTAssertTrue(lifecycle.showsLayers)

        lifecycle.finishRetraction(ifItemIsCompleted: false)
        XCTAssertFalse(lifecycle.showsLayers)
    }

    func testRapidRecompletionPreventsStaleCleanup() {
        var lifecycle = LedgerCompletionLayerLifecycle(isCompleted: true)
        lifecycle.beginTransition(to: false)
        lifecycle.beginTransition(to: true)
        lifecycle.finishRetraction(ifItemIsCompleted: true)

        XCTAssertEqual(lifecycle.progress, 1)
        XCTAssertTrue(lifecycle.showsLayers)
    }

    func testReducedMotionUsesItsOwnCleanupDuration() {
        XCTAssertEqual(
            LedgerCompletionLayerLifecycle.cleanupDelay(reduceMotion: false),
            NotchMotion.completionRetractDuration
        )
        XCTAssertEqual(
            LedgerCompletionLayerLifecycle.cleanupDelay(reduceMotion: true),
            NotchMotion.reducedMotionDuration
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

    func testBulgeIsZeroDuringCirclePhaseAndAtRest() {
        for progress: CGFloat in [0, 0.05, 0.13] {
            XCTAssertEqual(
                LedgerCompletionRevealGeometry.bulge(in: rowRect, progress: progress),
                0,
                "Expected no bulge during the circle phase at \(progress)"
            )
        }

        for height: CGFloat in [56, 64, 66] {
            let rect = CGRect(x: 0, y: 0, width: 420, height: height)
            XCTAssertEqual(LedgerCompletionRevealGeometry.bulge(in: rect, progress: 1), 0)
        }
    }

    func testBulgePeaksMidSweepAndStaysBounded() {
        let circlePhaseEnd = rowRect.height / rowRect.width
        let midSweep = (circlePhaseEnd + 1) / 2
        let mid = LedgerCompletionRevealGeometry.bulge(in: rowRect, progress: midSweep)
        let early = LedgerCompletionRevealGeometry.bulge(in: rowRect, progress: 0.25)
        let late = LedgerCompletionRevealGeometry.bulge(in: rowRect, progress: 0.9)

        XCTAssertGreaterThan(mid, early)
        XCTAssertGreaterThan(mid, late)

        for progress in stride(from: CGFloat.zero, through: 1, by: 0.02) {
            XCTAssertLessThanOrEqual(
                LedgerCompletionRevealGeometry.bulge(in: rowRect, progress: progress),
                LedgerCompletionRevealGeometry.bulgeFactor * rowRect.height
            )
        }
    }

    func testFrontApexNeverLeavesTheRowAndAdvancesMonotonically() {
        let apexes = stride(from: CGFloat.zero, through: 1, by: 0.02).map {
            LedgerCompletionRevealGeometry.frontApexX(in: rowRect, progress: $0)
        }

        for apex in apexes {
            XCTAssertLessThanOrEqual(apex, rowRect.maxX)
        }
        for pair in zip(apexes, apexes.dropFirst()) {
            XCTAssertLessThanOrEqual(pair.0, pair.1)
        }
    }

    func testMeniscusPathExactlyCoversTheRowWhenSettled() {
        for height: CGFloat in [56, 64, 66] {
            let rect = CGRect(x: 0, y: 0, width: 420, height: height)
            let path = LedgerCompletionRevealGeometry.meniscusPath(in: rect, progress: 1)

            XCTAssertEqual(path.boundingRect, rect)
            XCTAssertTrue(path.contains(CGPoint(x: rect.maxX - 0.5, y: rect.midY)))
        }
    }

    func testMeniscusPathMatchesCirclePhaseShape() {
        let progress: CGFloat = 0.05
        let frame = LedgerCompletionRevealGeometry.revealFrame(
            in: rowRect,
            progress: progress
        )
        let bounds = LedgerCompletionRevealGeometry.meniscusPath(
            in: rowRect,
            progress: progress
        ).boundingRect

        XCTAssertEqual(bounds.minX, frame.minX, accuracy: 0.001)
        XCTAssertEqual(bounds.maxX, frame.maxX, accuracy: 0.001)
        XCTAssertEqual(bounds.width, bounds.height, accuracy: 0.001)
    }

    func testMeniscusPathIsEmptyAtZeroProgress() {
        XCTAssertTrue(
            LedgerCompletionRevealGeometry.meniscusPath(in: rowRect, progress: 0).isEmpty
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

    func testShadowPanelIsNoninteractiveAndCannotBecomeKeyOrMain() {
        let controller = PanelController(automaticDismissalEnabled: false) { _ in
            AnyView(EmptyView())
        }

        XCTAssertTrue(controller.shadowPanel.ignoresMouseEvents)
        XCTAssertFalse(controller.shadowPanel.canBecomeKey)
        XCTAssertFalse(controller.shadowPanel.canBecomeMain)
        XCTAssertFalse(controller.shadowPanel.hasShadow)
        XCTAssertFalse(controller.shadowPanel.isAccessibilityElement())
    }

    func testSystemHelperWindowsDoNotSuppressOutsideClickDismissal() {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        // A visible non-dialog window (like the text-input TUINSWindow that
        // appears whenever a text field is focused) must not count as an
        // auxiliary dialog — that silently disables outside-click dismissal.
        let helper = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 10, height: 10),
            styleMask: [.borderless],
            backing: .buffered,
            defer: true
        )
        helper.orderFrontRegardless()
        defer { helper.orderOut(nil) }

        XCTAssertTrue(helper.isVisible)
        XCTAssertFalse(
            PanelDismissalEventPolicy.countsAsAuxiliaryDialog(helper, panel: panel, modalWindow: nil)
        )
        // A window running as the app modal (alerts, import/export dialogs)
        // does count.
        XCTAssertTrue(
            PanelDismissalEventPolicy.countsAsAuxiliaryDialog(helper, panel: panel, modalWindow: helper)
        )
        // The panel itself never counts.
        XCTAssertFalse(
            PanelDismissalEventPolicy.countsAsAuxiliaryDialog(panel, panel: panel, modalWindow: nil)
        )
    }

    func testPresentWithoutDisplayGeometryReportsDismissalInsteadOfDesyncing() {
        let controller = PanelController(
            displayLocator: UnavailableDisplayLocator(),
            automaticDismissalEnabled: false
        ) { _ in
            AnyView(EmptyView())
        }
        var reportedReason: PanelDismissalReason?
        controller.onRequestDismiss = { reportedReason = $0 }

        controller.present(.expanded, activate: false)

        XCTAssertEqual(controller.state, .dormant)
        XCTAssertFalse(controller.panel.isVisible)
        XCTAssertEqual(reportedReason, .automatic)
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

@MainActor
private final class UnavailableDisplayLocator: DisplayLocating {
    var screens: [NSScreen] { [] }
    var pointerScreen: NSScreen? { nil }
    func screen(withID displayID: CGDirectDisplayID) -> NSScreen? { nil }
    func displayID(for screen: NSScreen) -> CGDirectDisplayID? { nil }
    func geometry(for screen: NSScreen) -> NotchGeometry? { nil }
}

final class PanelWindowInteractionPolicyTests: XCTestCase {
    func testSurfaceStaysInTheStatusBarPlane() {
        XCTAssertEqual(PanelWindowLevelPolicy.surfaceLevel, .statusBar)
    }

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

    func testOversizedTransitionCanvasSuspendsHitTestingUntilTheTargetFrameSettles() {
        let canvas = CGRect(x: 482, y: 422, width: 440, height: 560)
        let target = CGRect(x: 612, y: 948, width: 180, height: 34)

        XCTAssertTrue(PanelWindowInteractionPolicy.suspendsHitTesting(
            transitionCanvasFrame: canvas,
            targetFrame: target
        ))
        XCTAssertFalse(PanelWindowInteractionPolicy.suspendsHitTesting(
            transitionCanvasFrame: target,
            targetFrame: target
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
