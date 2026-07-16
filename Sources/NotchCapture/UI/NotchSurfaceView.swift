import SwiftUI

struct NotchSurfaceView: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayedState: AppViewModel.SurfaceState
    @State private var activeTransition: AnyTransition = .opacity

    init(viewModel: AppViewModel) {
        self.viewModel = viewModel
        _displayedState = State(initialValue: viewModel.surfaceState)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Group {
                switch displayedState {
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
            .id(contentIdentity(for: displayedState))
            .transition(activeTransition)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipped()
        .onChange(of: viewModel.surfaceState) { oldState, newState in
            if isDropOnlyTransition(from: oldState, to: newState) {
                displayedState = newState
                return
            }

            activeTransition = transition(from: oldState, to: newState)
            withAnimation(reduceMotion ? NotchMotion.reducedMotion : NotchMotion.content) {
                displayedState = newState
            }
        }
        .preferredColorScheme(.dark)
    }

    private func isDropOnlyTransition(
        from oldState: AppViewModel.SurfaceState,
        to newState: AppViewModel.SurfaceState
    ) -> Bool {
        (oldState == .expanded && newState == .drop)
            || (oldState == .drop && newState == .expanded)
    }

    private func contentIdentity(for state: AppViewModel.SurfaceState) -> String {
        switch state {
        case .expanded, .drop: "expanded"
        case .dormant: "dormant"
        case .collapsed: "collapsed"
        case .confirmation: "confirmation"
        case .screenshot: "screenshot"
        case .onboarding: "onboarding"
        case .settings: "settings"
        }
    }

    private func transition(
        from oldState: AppViewModel.SurfaceState,
        to newState: AppViewModel.SurfaceState
    ) -> AnyTransition {
        guard !reduceMotion else { return .opacity }

        if oldState == .expanded && newState == .settings {
            return .asymmetric(
                insertion: .opacity.combined(with: .offset(x: 8)),
                removal: .opacity.combined(with: .offset(x: -8))
            )
        }
        if oldState == .settings && newState == .expanded {
            return .asymmetric(
                insertion: .opacity.combined(with: .offset(x: -8)),
                removal: .opacity.combined(with: .offset(x: 8))
            )
        }
        if newState == .confirmation {
            return .asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.985, anchor: .top)),
                removal: .opacity
            )
        }

        return .opacity.combined(with: .offset(y: -4))
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
                    .frame(width: 38, height: 1)
                    .scaleEffect(x: isHovered ? 1 : 22 / 38)
                    .padding(.bottom, 3)
            }
            .clipShape(NotchHugShape(bottomRadius: 16))
            .contentShape(NotchHugShape(bottomRadius: 16))
            .shadow(color: .black.opacity(0.36), radius: 16, y: 8)
        }
        .buttonStyle(NotchPressButtonStyle(pressedScale: 0.985, pressedOpacity: 0.94))
        .notchHitTarget(NotchHugShape(bottomRadius: 16))
        .onHover { isHovered = $0 }
        .animation(NotchMotion.hover, value: isHovered)
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
                .buttonStyle(CompactTextButtonStyle())
                .notchHitTarget(Rectangle())
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
