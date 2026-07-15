import SwiftUI

struct ConfirmationView: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: false)) { context in
            let progress = remainingProgress(at: context.date)

            HStack(spacing: 11) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.09), lineWidth: 2)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(NotchTheme.mint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(NotchTheme.mint)
                }
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)

                Text("Saved to \(viewModel.confirmation?.destination ?? "Inbox")")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(NotchTheme.primaryText)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Button("Undo") {
                    viewModel.undoConfirmation()
                }
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(NotchTheme.mint)
                .buttonStyle(CompactTextButtonStyle())
                .notchHitTarget(Rectangle())
                .keyboardShortcut("z", modifiers: .command)
                .accessibilityHint("Removes the item that was just captured")
            }
            .padding(.horizontal, 14)
            .frame(width: 280, height: 56)
            .background(NotchSurfaceBackground())
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Captured. Saved to \(viewModel.confirmation?.destination ?? "Inbox")")
        }
    }

    private func remainingProgress(at date: Date) -> Double {
        if reduceMotion { return 1 }
        guard let expiresAt = viewModel.confirmation?.expiresAt else { return 0 }
        return max(0, min(1, expiresAt.timeIntervalSince(date) / 5))
    }
}
