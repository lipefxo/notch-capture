import Foundation

/// The mutually-exclusive presentation states supported by the notch panel.
///
/// Item content deliberately lives outside this type. Keeping presentation state
/// payload-free lets the app's view model own capture data without coupling the
/// AppKit window layer to persistence models.
public enum PanelState: String, CaseIterable, Hashable, Sendable {
    case dormant
    case collapsed
    case confirmation
    case expanded
    case dropTarget
    case screenshot
    case onboarding
    case settings

    public var isVisible: Bool {
        self != .dormant && self != .screenshot
    }

    public var isExplicitSession: Bool {
        switch self {
        case .confirmation, .expanded, .dropTarget, .onboarding, .settings:
            return true
        case .dormant, .collapsed, .screenshot:
            return false
        }
    }

    public var acceptsKeyboardInput: Bool {
        switch self {
        case .expanded, .dropTarget, .onboarding, .settings:
            return true
        case .dormant, .collapsed, .confirmation, .screenshot:
            return false
        }
    }

    var nominalSize: CGSize {
        switch self {
        case .collapsed:
            CGSize(width: 178, height: 34)
        case .confirmation:
            CGSize(width: 280, height: 56)
        case .expanded, .dropTarget, .settings:
            CGSize(width: 420, height: 560)
        case .onboarding:
            CGSize(width: 420, height: 500)
        case .dormant, .screenshot:
            .zero
        }
    }
}
