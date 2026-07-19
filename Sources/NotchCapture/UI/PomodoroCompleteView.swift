import SwiftUI

struct PomodoroCompleteView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        HStack(spacing: 9) {
            ZStack {
                Circle().fill(NotchTheme.primaryAccent)
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(NotchTheme.ink)
            }
            .frame(width: 24, height: 24)
            .fixedSize()

            Text("Focus complete")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(NotchTheme.primaryText)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
            Spacer(minLength: 4)
            HStack(spacing: 0) {
                Button("Done") {
                    viewModel.acknowledgePomodoro()
                    viewModel.dismiss()
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(NotchTheme.secondaryText)
                .buttonStyle(CompactTextButtonStyle())

                Button("Restart") {
                    viewModel.acknowledgePomodoro()
                    viewModel.togglePomodoro()
                    viewModel.openExpanded()
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(NotchTheme.primaryAccent)
                .buttonStyle(CompactTextButtonStyle())
            }
            .fixedSize()
            .layoutPriority(2)
        }
        .padding(.horizontal, 12)
        .frame(width: 280, height: 56)
    }
}
