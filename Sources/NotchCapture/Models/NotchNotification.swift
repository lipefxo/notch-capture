import Foundation

/// Content shown in the reusable notch-native notification surface. Producers
/// keep a stable `id` so lifecycle updates replace the current content in place.
struct NotchNotification: Identifiable, Equatable, Sendable {
    enum Tone: Equatable, Sendable {
        case neutral
        case positive
        case warning
        case error
    }

    enum Progress: Equatable, Sendable {
        case none
        case indeterminate
        case fraction(Double)

        var normalizedFraction: Double? {
            guard case let .fraction(value) = self, value.isFinite else { return nil }
            return min(max(value, 0), 1)
        }
    }

    struct Action: Identifiable, Equatable, Sendable {
        enum Emphasis: Equatable, Sendable {
            case secondary
            case primary
        }

        let id: String
        let title: String
        var emphasis: Emphasis = .secondary
        var dismissesNotification = false
    }

    let id: String
    var systemImage: String
    var tone: Tone
    var title: String
    var detail: String?
    var progress: Progress = .none
    var secondaryAction: Action?
    var primaryAction: Action?
    /// Action used by Escape/outside-click. Nil means hide the surface while
    /// retaining the notification for future in-focus/background updates.
    var dismissalActionID: String?
    var accessibilityText: String
    var autoDismissAfter: TimeInterval?
    var autoDismissActionID: String?

    var actions: [Action] {
        [secondaryAction, primaryAction].compactMap { $0 }
    }
}

enum NotchNotificationDelivery: Equatable, Sendable {
    /// Reveal now, temporarily interrupting and later restoring the surface.
    case immediate
    /// Replace by key now, but reveal only when an idle surface is available.
    case whenIdle
    /// Update an existing active/queued notification without revealing it.
    case backgroundUpdate
}
