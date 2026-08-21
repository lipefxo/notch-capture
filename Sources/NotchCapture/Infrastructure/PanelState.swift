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
    case volume
    case confirmation
    case notification
    case expanded
    case dropTarget
    case onboarding
    case settings
    case mirror

    public var isVisible: Bool {
        self != .dormant
    }

    /// The mirror is deliberately excluded: a webcam preview that vanishes the
    /// moment you click into another app cannot do its job, so it opts out of
    /// the Escape/outside-click dismissal monitors and closes only on request.
    public var isExplicitSession: Bool {
        switch self {
        case .volume, .confirmation, .notification, .expanded, .dropTarget, .onboarding, .settings:
            return true
        case .dormant, .collapsed, .collapsedActivity, .mirror:
            return false
        }
    }

    public var acceptsKeyboardInput: Bool {
        switch self {
        case .expanded, .dropTarget, .onboarding, .settings:
            return true
        case .dormant, .collapsed, .collapsedActivity, .volume, .confirmation, .notification, .mirror:
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
        case .volume:
            CGSize(width: 340, height: 56)
        case .confirmation:
            CGSize(width: 300, height: 56)
        case .notification:
            CGSize(width: 460, height: 72)
        case .expanded, .dropTarget, .settings:
            CGSize(
                width: NotchTheme.width + (NotchTheme.topFlare * 2),
                height: NotchTheme.maxHeight
            )
        case .onboarding:
            CGSize(
                width: NotchTheme.width + (NotchTheme.topFlare * 2),
                height: 500
            )
        case .mirror:
            CGSize(
                width: NotchTheme.width + (NotchTheme.topFlare * 2),
                height: NotchTheme.mirrorHeight
            )
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

    /// Compact widths reserve a fixed trailing slot for audio, keeping capture
    /// and transport content at its established size.
    static let audioControlSlot: CGFloat = 28

    static func capture(for presentationSize: CompactPresentationSize) -> Self {
        switch presentationSize {
        case .minimal:
            Self(shellSize: CGSize(width: 226, height: 34), contentSize: CGSize(width: 206, height: 34), bottomRadius: 16, wingWidth: nil)
        case .extended:
            Self(shellSize: CGSize(width: 332, height: 50), contentSize: CGSize(width: 312, height: 50), bottomRadius: 22, wingWidth: nil)
        }
    }

    static func externalActivity(for presentationSize: CompactPresentationSize) -> Self {
        switch presentationSize {
        case .minimal:
            Self(shellSize: CGSize(width: 328, height: 34), contentSize: CGSize(width: 308, height: 34), bottomRadius: 16, wingWidth: nil)
        case .extended:
            Self(shellSize: CGSize(width: 472, height: 56), contentSize: CGSize(width: 452, height: 56), bottomRadius: 22, wingWidth: nil)
        }
    }

    static func hardwareActivity(
        for presentationSize: CompactPresentationSize,
        notchWidth: CGFloat,
        notchBandHeight: CGFloat
    ) -> Self {
        let wingWidth: CGFloat = switch presentationSize {
        case .minimal: 0
        case .extended: NotchTheme.collapsedActivityWingWidth
        }
        let height = max(34, notchBandHeight + 4)
        return Self(
            shellSize: CGSize(width: notchWidth + (wingWidth * 2) + (NotchTheme.topFlare * 2), height: height),
            contentSize: CGSize(width: notchWidth + (wingWidth * 2), height: height),
            bottomRadius: 16,
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
