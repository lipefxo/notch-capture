import SwiftUI

/// Option 1: a quiet, single-row update surface that grows directly from the
/// notch. Its 440pt content body sits inside the shared 10pt top flares.
struct NotchNotificationView: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let notification = viewModel.notification {
                content(notification)
                    .id(contentIdentity(notification))
                    .transition(.opacity)
                    .task(id: autoDismissIdentity(notification)) {
                        guard let delay = notification.autoDismissAfter,
                              let actionID = notification.autoDismissActionID else { return }
                        try? await Task.sleep(for: .seconds(delay))
                        guard !Task.isCancelled,
                              viewModel.notification?.id == notification.id,
                              viewModel.notification?.autoDismissActionID == actionID else { return }
                        viewModel.performNotificationAction(actionID)
                    }
            }
        }
        .animation(
            reduceMotion ? NotchMotion.reducedMotion : NotchMotion.notification,
            value: viewModel.notification
        )
        .frame(width: 440, height: 72)
    }

    private func content(_ notification: NotchNotification) -> some View {
        HStack(spacing: 0) {
            statusIcon(notification)
                .frame(width: 28, height: 28)
                .padding(.trailing, 10)

            VStack(alignment: .leading, spacing: 3) {
                Text(notification.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NotchTheme.primaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if let detail = notification.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 10.5, weight: .regular))
                        .foregroundStyle(NotchTheme.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            ForEach(notification.actions) { action in
                Rectangle()
                    .fill(NotchTheme.hairline)
                    .frame(width: 1, height: 32)
                    .padding(.leading, 10)
                    .accessibilityHidden(true)

                Button(action.title) {
                    viewModel.performNotificationAction(action.id)
                }
                .font(.system(
                    size: 11.5,
                    weight: action.emphasis == .primary ? .semibold : .regular
                ))
                .foregroundStyle(
                    action.emphasis == .primary
                        ? NotchTheme.completionAccent
                        : NotchTheme.secondaryText
                )
                .buttonStyle(NotchPressButtonStyle(pressedScale: 0.97, pressedOpacity: 0.68))
                .frame(minWidth: action.emphasis == .primary ? 68 : 58, minHeight: 44)
                .contentShape(Rectangle())
                .accessibilityHint(actionAccessibilityHint(action, notification: notification))
            }
        }
        .padding(.horizontal, 14)
        .frame(width: 440, height: 72)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(notification.accessibilityText)
    }

    @ViewBuilder
    private func statusIcon(_ notification: NotchNotification) -> some View {
        let accent = toneColor(notification.tone)
        ZStack {
            Circle()
                .stroke(accent.opacity(0.22), lineWidth: 1.5)

            switch notification.progress {
            case .none:
                Image(systemName: notification.systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(accent)
            case .indeterminate:
                ProgressView()
                    .controlSize(.small)
                    .tint(accent)
                    .scaleEffect(0.66)
            case .fraction:
                Circle()
                    .trim(from: 0, to: notification.progress.normalizedFraction ?? 0)
                    .stroke(accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(2)
                Image(systemName: notification.systemImage)
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(accent)
            }
        }
        .accessibilityHidden(true)
    }

    private func toneColor(_ tone: NotchNotification.Tone) -> Color {
        switch tone {
        case .neutral, .positive: NotchTheme.completionAccent
        case .warning: NotchTheme.warning
        case .error: NotchTheme.destructive
        }
    }

    private func contentIdentity(_ notification: NotchNotification) -> String {
        "\(notification.id)|\(notification.title)|\(notification.detail ?? "")"
    }

    private func autoDismissIdentity(_ notification: NotchNotification) -> String {
        "\(contentIdentity(notification))|\(notification.autoDismissActionID ?? "")"
    }

    private func actionAccessibilityHint(
        _ action: NotchNotification.Action,
        notification: NotchNotification
    ) -> String {
        "\(action.title) for \(notification.title)"
    }
}
