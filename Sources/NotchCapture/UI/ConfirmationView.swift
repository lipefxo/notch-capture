import SwiftUI

struct ConfirmationView: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false
    @State private var contentIsVisible = false
    @State private var stagingGeneration = 0

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: 1 / 30,
                paused: reduceMotion || viewModel.confirmation?.isPaused == true
            )
        ) { context in
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
                .opacity(contentIsVisible ? 1 : 0)
                .scaleEffect(reduceMotion || contentIsVisible ? 1 : 0.88)
                .animation(
                    reduceMotion ? NotchMotion.reducedMotion : NotchMotion.confirmation,
                    value: contentIsVisible
                )
                .accessibilityHidden(true)

                Text("Saved to \(viewModel.confirmation?.destination ?? "Inbox")")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(NotchTheme.primaryText)
                    .lineLimit(1)
                    .opacity(contentIsVisible ? 1 : 0)
                    .offset(y: reduceMotion || contentIsVisible ? 0 : 2)
                    .animation(supportingAnimation, value: contentIsVisible)

                Spacer(minLength: 8)

                Button("Undo") {
                    viewModel.undoConfirmation()
                }
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(NotchTheme.mint)
                .buttonStyle(CompactTextButtonStyle())
                .notchHitTarget(Rectangle())
                // No keyboard shortcut: the confirmation panel never becomes
                // key (the source app keeps focus), so one could never fire.
                .opacity(contentIsVisible ? 1 : 0)
                .offset(y: reduceMotion || contentIsVisible ? 0 : 2)
                .animation(supportingAnimation, value: contentIsVisible)
                .accessibilityHint("Removes the item that was just captured")
            }
            .padding(.horizontal, 14)
            .frame(width: 280, height: 56)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Captured. Saved to \(viewModel.confirmation?.destination ?? "Inbox")")
        }
        .onHover { hovered in
            isHovered = hovered
            viewModel.setConfirmationPaused(hovered)
        }
        .onAppear { stageContent() }
        .onChange(of: viewModel.confirmation?.itemID) { _, _ in
            stageContent()
            if isHovered { viewModel.setConfirmationPaused(true) }
        }
    }

    private func remainingProgress(at date: Date) -> Double {
        if reduceMotion { return 1 }
        return viewModel.confirmation?.progress(at: date) ?? 0
    }

    private var supportingAnimation: Animation {
        if reduceMotion { return NotchMotion.reducedMotion }
        return NotchMotion.confirmation.delay(NotchMotion.stagingDelay)
    }

    private func stageContent() {
        stagingGeneration &+= 1
        let generation = stagingGeneration
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            contentIsVisible = false
        }
        Task { @MainActor in
            await Task.yield()
            guard generation == stagingGeneration else { return }
            contentIsVisible = true
        }
    }
}
