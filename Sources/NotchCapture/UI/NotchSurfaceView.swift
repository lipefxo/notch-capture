import SwiftUI

struct NotchSurfaceView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        Group {
            switch viewModel.surfaceState {
            case .dormant:
                EmptyView()
            case .collapsed:
                CollapsedPillView(viewModel: viewModel)
            case .confirmation:
                ConfirmationView(viewModel: viewModel)
            case .expanded, .drop:
                ExpandedInboxView(viewModel: viewModel)
            case .screenshot:
                ScreenshotStateView(viewModel: viewModel)
            case .onboarding:
                OnboardingView(viewModel: viewModel)
            case .settings:
                SettingsView(viewModel: viewModel)
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct CollapsedPillView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var isHovered = false

    var body: some View {
        Button {
            viewModel.openExpanded()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(NotchTheme.mint)
                Text("Capture")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.82))
                Text("⌃⇧N")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(NotchTheme.tertiaryText)
            }
            .frame(width: 178, height: 34)
            .background(NotchTheme.ink.opacity(0.98))
            .overlay(alignment: .bottom) {
                Capsule()
                    .fill(isHovered ? NotchTheme.mint.opacity(0.65) : Color.white.opacity(0.1))
                    .frame(width: isHovered ? 38 : 22, height: 1)
                    .padding(.bottom, 3)
            }
            .clipShape(NotchHugShape(bottomRadius: 16))
            .contentShape(NotchHugShape(bottomRadius: 16))
            .shadow(color: .black.opacity(0.36), radius: 16, y: 8)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Open Notch Capture")
        .accessibilityLabel("Open Notch Capture")
        .accessibilityHint("Opens the capture composer and inbox")
    }
}

struct ScreenshotStateView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "viewfinder")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(NotchTheme.mint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Select a region")
                    .font(.system(size: 13, weight: .semibold))
                Text("Drag anywhere on screen · Esc to cancel")
                    .font(.system(size: 11))
                    .foregroundStyle(NotchTheme.secondaryText)
            }
            Spacer()
            Button("Cancel") { viewModel.dismiss() }
                .buttonStyle(.plain)
                .foregroundStyle(NotchTheme.secondaryText)
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 18)
        .frame(width: 360, height: 64)
        .background(NotchSurfaceBackground())
        .accessibilityElement(children: .contain)
    }
}

#if DEBUG
#Preview("Expanded") {
    NotchSurfaceView(viewModel: .preview)
        .padding(40)
        .background(Color.gray.opacity(0.35))
}

#Preview("Collapsed") {
    let model = AppViewModel.preview
    model.surfaceState = .collapsed
    return NotchSurfaceView(viewModel: model)
        .padding(40)
}
#endif
