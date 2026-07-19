import SwiftUI

struct OnboardingView: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var navigationDirection: CGFloat = 1

    var body: some View {
        VStack(spacing: 0) {
            onboardingHeader

            Group {
                switch viewModel.onboardingStep {
                case .welcome:
                    welcomePage
                case .shortcuts:
                    shortcutsPage
                case .permission:
                    permissionPage
                }
            }
            .id(viewModel.onboardingStep)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(pageTransition)

            onboardingFooter
        }
        .frame(width: NotchTheme.width, height: 500)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Notch Capture setup")
    }

    private var onboardingHeader: some View {
        HStack(spacing: 9) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(NotchTheme.mint)
            Text("Notch Capture")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(NotchTheme.primaryText)
                .fixedSize()
            Spacer()
            Text("Step \(viewModel.onboardingStep.number) of \(AppViewModel.OnboardingStep.allCases.count)")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(NotchTheme.tertiaryText)
                .fixedSize()
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(NotchTheme.ink)
        .overlay(alignment: .bottom) {
            Rectangle().fill(NotchTheme.hairline).frame(height: 1)
        }
    }

    private var welcomePage: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 20)

            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(NotchTheme.mint.opacity(0.09))
                    .frame(width: 88, height: 66)
                Image(systemName: "tray.and.arrow.down.fill")
                    .font(.system(size: 29, weight: .light))
                    .foregroundStyle(NotchTheme.mint)
            }

            VStack(spacing: 7) {
                Text("Capture without breaking focus")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(NotchTheme.primaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Save what matters from any app, then get straight back to what you were doing.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(NotchTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .frame(maxWidth: 300)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 7) {
                OnboardingCapability(symbol: "text.quote", title: "Selections")
                OnboardingCapability(symbol: "note.text", title: "Notes")
                OnboardingCapability(symbol: "paperclip", title: "Files")
            }
            .padding(.top, 4)

            Spacer(minLength: 20)
        }
        .padding(.horizontal, 28)
    }

    private var shortcutsPage: some View {
        VStack(spacing: 17) {
            Spacer(minLength: 18)

            VStack(spacing: 7) {
                Text("Two shortcuts, one inbox")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(NotchTheme.primaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Capture what is already selected, or open the inbox to write and attach anything.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(NotchTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .frame(maxWidth: 305)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 0) {
                OnboardingShortcutRow(
                    symbol: "text.cursor",
                    title: "Capture selection",
                    detail: "Save selected text from the frontmost app",
                    shortcut: viewModel.shortcutDisplayValue(for: .captureSelection)
                )
                Rectangle()
                    .fill(NotchTheme.hairline)
                    .frame(height: 1)
                    .padding(.leading, 48)
                OnboardingShortcutRow(
                    symbol: "square.and.pencil",
                    title: "Open Notch Capture",
                    detail: "Write a note or add a file",
                    shortcut: viewModel.shortcutDisplayValue(for: .openComposer)
                )
            }
            .background(Color.white.opacity(0.035))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(NotchTheme.hairline, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text("You can change both shortcuts later in Settings.")
                .font(.system(size: 10))
                .foregroundStyle(NotchTheme.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 18)
        }
        .padding(.horizontal, 28)
    }

    private var permissionPage: some View {
        VStack(spacing: 17) {
            Spacer(minLength: 18)

            VStack(spacing: 7) {
                Text("Allow selected-text capture")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(NotchTheme.primaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Accessibility lets Notch Capture read only the selection you ask it to capture. Everything stays on this Mac.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(NotchTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .frame(maxWidth: 315)
                    .fixedSize(horizontal: false, vertical: true)
            }

            OnboardingPermissionRow(
                isGranted: viewModel.accessibilityGranted,
                action: viewModel.hooks.onRequestAccessibility
            )

            if viewModel.accessibilityGranted {
                Label("Ready to capture selected text", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(NotchTheme.mint)
                    .fixedSize()
            } else {
                Text("You can continue without allowing access. The selection shortcut will ask again when you use it.")
                    .font(.system(size: 10))
                    .foregroundStyle(NotchTheme.tertiaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .frame(maxWidth: 300)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 18)
        }
        .padding(.horizontal, 28)
    }

    private var onboardingFooter: some View {
        HStack {
            if viewModel.onboardingStep != .welcome {
                Button("Back", action: moveBackward)
                    .buttonStyle(CompactTextButtonStyle())
                    .notchHitTarget(Rectangle())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(NotchTheme.secondaryText)
                    .fixedSize()
            } else {
                Color.clear.frame(width: 42, height: 1)
            }

            Spacer()

            HStack(spacing: 5) {
                ForEach(AppViewModel.OnboardingStep.allCases) { step in
                    Capsule()
                        .fill(step == viewModel.onboardingStep ? NotchTheme.mint : Color.white.opacity(0.14))
                        .frame(width: step == viewModel.onboardingStep ? 14 : 5, height: 5)
                }
            }
            .animation(reduceMotion ? nil : NotchMotion.filter, value: viewModel.onboardingStep)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "Step \(viewModel.onboardingStep.number) of \(AppViewModel.OnboardingStep.allCases.count)"
            )

            Spacer()

            Button(viewModel.onboardingStep == .permission ? "Open inbox" : "Continue") {
                if viewModel.onboardingStep == .permission {
                    viewModel.finishOnboarding()
                } else {
                    moveForward()
                }
            }
            .buttonStyle(MintButtonStyle())
            .notchHitTarget(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 16)
        .frame(height: 58)
        .background(NotchTheme.ink)
        .overlay(alignment: .top) {
            Rectangle().fill(NotchTheme.hairline).frame(height: 1)
        }
    }

    private func moveForward() {
        navigationDirection = 1
        withAnimation(reduceMotion ? NotchMotion.reducedMotion : NotchMotion.onboarding) {
            viewModel.advanceOnboarding()
        }
    }

    private func moveBackward() {
        navigationDirection = -1
        withAnimation(reduceMotion ? NotchMotion.reducedMotion : NotchMotion.onboarding) {
            viewModel.retreatOnboarding()
        }
    }

    private var pageTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(x: 10 * navigationDirection)),
            removal: .opacity.combined(with: .offset(x: -10 * navigationDirection))
        )
    }
}

private struct OnboardingCapability: View {
    let symbol: String
    let title: String

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 9.5, weight: .medium))
            .foregroundStyle(NotchTheme.secondaryText)
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(Color.white.opacity(0.045))
            .clipShape(Capsule())
    }
}

private struct OnboardingShortcutRow: View {
    let symbol: String
    let title: String
    let detail: String
    let shortcut: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(NotchTheme.mint)
                .frame(width: 30, height: 30)
                .background(NotchTheme.mint.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(NotchTheme.primaryText)
                Text(detail)
                    .font(.system(size: 9.5))
                    .foregroundStyle(NotchTheme.secondaryText)
            }
            Spacer(minLength: 8)
            ShortcutKeycap(value: shortcut)
        }
        .padding(.horizontal, 11)
        .frame(height: 57)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(shortcut). \(detail)")
    }
}

private struct OnboardingPermissionRow: View {
    let isGranted: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "cursorarrow.rays")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isGranted ? NotchTheme.mint : Color.white.opacity(0.68))
                .frame(width: 32, height: 32)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("Accessibility")
                    .font(.system(size: 11, weight: .semibold))
                Text(isGranted ? "Selected-text capture is enabled" : "Required only for selected-text capture")
                    .font(.system(size: 9.5))
                    .foregroundStyle(NotchTheme.secondaryText)
            }
            Spacer()
            if isGranted {
                Label("Allowed", systemImage: "checkmark")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(NotchTheme.mint)
            } else {
                Button("Allow", action: action)
                    .buttonStyle(MintButtonStyle())
                    .notchHitTarget(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
        }
        .padding(.horizontal, 11)
        .frame(height: 56)
        .background(Color.white.opacity(0.035))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(NotchTheme.hairline, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Accessibility, \(isGranted ? "allowed" : "not allowed")")
    }
}
