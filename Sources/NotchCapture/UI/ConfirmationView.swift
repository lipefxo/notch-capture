import SwiftUI

struct ConfirmationView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: false)) { context in
            let progress = remainingProgress(at: context.date)

            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.09), lineWidth: 2)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(NotchTheme.mint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(NotchTheme.mint)
                }
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.confirmation?.title ?? "Captured")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                    Text("Saved to \(viewModel.confirmation?.destination ?? "Inbox")")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(NotchTheme.secondaryText)
                }

                Spacer(minLength: 8)

                Button("Undo") {
                    viewModel.undoConfirmation()
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(NotchTheme.mint)
                .buttonStyle(.plain)
                .keyboardShortcut("z", modifiers: .command)
                .accessibilityHint("Removes the item that was just captured")
            }
            .padding(.horizontal, 16)
            .frame(width: 344, height: 62)
            .background(NotchSurfaceBackground())
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Captured. Saved to \(viewModel.confirmation?.destination ?? "Inbox")")
        }
    }

    private func remainingProgress(at date: Date) -> Double {
        guard let expiresAt = viewModel.confirmation?.expiresAt else { return 0 }
        return max(0, min(1, expiresAt.timeIntervalSince(date) / 5))
    }
}
