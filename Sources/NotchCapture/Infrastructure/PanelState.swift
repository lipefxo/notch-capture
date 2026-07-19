import Foundation

/// The density preset used by the passive compact surfaces.  Keep this type
/// independent of SwiftUI so AppKit geometry and preference restoration can
/// share it without pulling UI code into the window layer.
public enum CompactPresentationSize: String, CaseIterable, Identifiable, Sendable {
    case minimal
    case extended

    public var id: Self { self }

    static func fromStoredValue(_ value: String?) -> Self {
        Self(rawValue: value ?? "") ?? .minimal
    }
}

/// The mutually-exclusive presentation states supported by the notch panel.
///
/// Item content deliberately lives outside this type. Keeping presentation state
/// payload-free lets the app's view model own capture data without coupling the
/// AppKit window layer to persistence models.
public enum PanelState: String, CaseIterable, Hashable, Sendable {
    case dormant
    case collapsed
    case collapsedActivity
    case confirmation
    case expanded
    case dropTarget
    case onboarding
    case settings

    public var isVisible: Bool {
        self != .dormant
    }

    public var isExplicitSession: Bool {
        switch self {
        case .confirmation, .expanded, .dropTarget, .onboarding, .settings:
            return true
        case .dormant, .collapsed, .collapsedActivity:
            return false
        }
    }

    public var acceptsKeyboardInput: Bool {
        switch self {
        case .expanded, .dropTarget, .onboarding, .settings:
            return true
        case .dormant, .collapsed, .collapsedActivity, .confirmation:
            return false
        }
    }

    /// Widths include the concave top-flare wings (`NotchTheme.topFlare` per side)
    /// that merge the surface into the screen edge; the visible body is 20pt narrower.
    var nominalSize: CGSize {
        nominalSize(compactPresentationSize: .minimal)
    }

    /// The static compact sizes. Hardware-notch activity is resolved through
    /// `CompactSurfaceMetrics`, because its width depends on the display.
    func nominalSize(compactPresentationSize: CompactPresentationSize) -> CGSize {
        switch self {
        case .collapsed:
            CompactSurfaceMetrics.capture(for: compactPresentationSize).shellSize
        case .collapsedActivity:
            CompactSurfaceMetrics.externalActivity(for: compactPresentationSize).shellSize
        case .confirmation:
            CGSize(width: 300, height: 56)
        case .expanded, .dropTarget, .settings:
            CGSize(width: 440, height: 560)
        case .onboarding:
            CGSize(width: 440, height: 500)
        case .dormant:
            .zero
        }
    }
}

/// One source of truth for every compact shell and content measurement. The
/// shell includes the two `topFlare` wings; content is the visible body inside
/// those wings.
struct CompactSurfaceMetrics: Equatable {
    let shellSize: CGSize
    let contentSize: CGSize
    let bottomRadius: CGFloat
    let wingWidth: CGFloat?

    static func capture(for presentationSize: CompactPresentationSize) -> Self {
        switch presentationSize {
        case .minimal:
            Self(shellSize: CGSize(width: 198, height: 34), contentSize: CGSize(width: 178, height: 34), bottomRadius: 16, wingWidth: nil)
        case .extended:
            Self(shellSize: CGSize(width: 300, height: 50), contentSize: CGSize(width: 280, height: 50), bottomRadius: 22, wingWidth: nil)
        }
    }

    static func externalActivity(for presentationSize: CompactPresentationSize) -> Self {
        switch presentationSize {
        case .minimal:
            Self(shellSize: CGSize(width: 300, height: 34), contentSize: CGSize(width: 280, height: 34), bottomRadius: 16, wingWidth: nil)
        case .extended:
            Self(shellSize: CGSize(width: 440, height: 56), contentSize: CGSize(width: 420, height: 56), bottomRadius: 22, wingWidth: nil)
        }
    }

    static func hardwareActivity(
        for presentationSize: CompactPresentationSize,
        notchWidth: CGFloat,
        notchBandHeight: CGFloat
    ) -> Self {
        let wingWidth: CGFloat = presentationSize == .extended ? 176 : NotchTheme.collapsedActivityWingWidth
        let baseHeight: CGFloat = presentationSize == .extended ? 56 : 34
        let height = max(baseHeight, notchBandHeight + 4)
        return Self(
            shellSize: CGSize(width: notchWidth + (wingWidth * 2) + (NotchTheme.topFlare * 2), height: height),
            contentSize: CGSize(width: notchWidth + (wingWidth * 2), height: height),
            bottomRadius: presentationSize == .extended ? 22 : 16,
            wingWidth: wingWidth
        )
    }

    static func resolve(
        state: PanelState,
        presentationSize: CompactPresentationSize,
        activityLayout: AppViewModel.CollapsedActivityLayout? = nil
    ) -> Self? {
        switch state {
        case .collapsed:
            capture(for: presentationSize)
        case .collapsedActivity:
            if let activityLayout, activityLayout.hasHardwareNotch {
                hardwareActivity(
                    for: presentationSize,
                    notchWidth: activityLayout.notchWidth,
                    notchBandHeight: activityLayout.notchBandHeight
                )
            } else {
                externalActivity(for: presentationSize)
            }
        default:
            nil
        }
    }
}
