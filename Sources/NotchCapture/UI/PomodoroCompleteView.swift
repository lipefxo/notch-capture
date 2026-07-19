import SwiftUI

struct PomodoroCompleteView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        HStack(spacing: 11) {
            ZStack {
                Circle().fill(NotchTheme.mint)
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(NotchTheme.ink)
            }
            .frame(width: 24, height: 24)
            .fixedSize()

            Text("Focus session complete")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(NotchTheme.primaryText)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
            Spacer(minLength: 8)
            Button("Restart") {
                viewModel.acknowledgePomodoro()
                viewModel.togglePomodoro()
                viewModel.openExpanded()
            }
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(NotchTheme.mint)
            .buttonStyle(CompactTextButtonStyle())
            .fixedSize()
            .layoutPriority(2)
        }
        .padding(.horizontal, 14)
        .frame(width: 280, height: 56)
    }
}
