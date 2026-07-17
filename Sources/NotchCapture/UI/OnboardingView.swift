import SwiftUI

struct OnboardingView: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var navigationDirection: CGFloat = 1
    @State private var supportingContentIsVisible = false
    @State private var stagingGeneration = 0

    var body: some View {
        VStack(spacing: 0) {
            onboardingHeader

            Group {
                switch viewModel.onboardingPage {
                case 0: welcomePage
                case 1: companionPage
                default: permissionsPage
                }
            }
            .id(viewModel.onboardingPage)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(pageTransition)

            onboardingFooter
        }
        .frame(width: NotchTheme.width, height: 500)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Notch Capture setup")
        .onAppear { stageSupportingContent() }
    }

    private var onboardingHeader: some View {
        HStack {
            HStack(spacing: 7) {
                Image(systemName: "square.and.pencil")
                    .foregroundStyle(NotchTheme.mint)
                Text("NOTCH CAPTURE")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1)
            }
            Spacer()
            Text("SETUP")
                .font(.system(size: 9, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(NotchTheme.tertiaryText)
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(NotchTheme.ink)
        .overlay(alignment: .bottom) {
            Rectangle().fill(NotchTheme.hairline).frame(height: 1)
        }
    }

    private var welcomePage: some View {
        VStack(spacing: 17) {
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(NotchTheme.mint.opacity(0.09))
                    .frame(width: 88, height: 66)
                Image(systemName: "tray.and.arrow.down.fill")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(NotchTheme.mint)
            }
            Text("A pocket for what matters")
                .font(.system(size: 20, weight: .semibold))
            Text("Keep selected text, quick notes, files, and screenshots without leaving what you’re doing.")
                .font(.system(size: 11.5))
                .foregroundStyle(NotchTheme.secondaryText)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(maxWidth: 290)
                .onboardingSupportingMotion(
                    isVisible: supportingContentIsVisible,
                    reduceMotion: reduceMotion
                )

            HStack(spacing: 8) {
                ShortcutKeycap(value: "⌃⇧Space")
                Text("captures the current selection")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(NotchTheme.secondaryText)
            }
            .padding(.top, 4)
            .onboardingSupportingMotion(
                isVisible: supportingContentIsVisible,
                reduceMotion: reduceMotion
            )
            Spacer()
        }
        .padding(.horizontal, 30)
    }

    private var companionPage: some View {
        VStack(spacing: 18) {
            Spacer()
            HStack(spacing: 8) {
                MiniNotch(label: "FLOW", color: .white.opacity(0.4))
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NotchTheme.mint)
                MiniNotch(label: "CAPTURE", color: NotchTheme.mint)
            }
            Text("Made to share the notch")
                .font(.system(size: 20, weight: .semibold))
            Text("NotchFlow keeps the idle surface. Notch Capture appears only when you use a shortcut, then gives it straight back.")
                .font(.system(size: 11.5))
                .foregroundStyle(NotchTheme.secondaryText)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(maxWidth: 300)
                .onboardingSupportingMotion(
                    isVisible: supportingContentIsVisible,
                    reduceMotion: reduceMotion
                )

            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(NotchTheme.mint)
                Text("Automatic ownership is the recommended default")
                    .font(.system(size: 10, weight: .medium))
            }
            .padding(.horizontal, 11)
            .frame(height: 30)
            .background(NotchTheme.mint.opacity(0.08))
            .clipShape(Capsule())
            .onboardingSupportingMotion(
                isVisible: supportingContentIsVisible,
                reduceMotion: reduceMotion
            )
            Spacer()
        }
        .padding(.horizontal, 30)
    }

    private var permissionsPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()
            VStack(alignment: .leading, spacing: 6) {
                Text("Two permissions, on your terms")
                    .font(.system(size: 20, weight: .semibold))
                Text("Your captures stay on this Mac. Permissions are used only when you invoke their feature.")
                    .font(.system(size: 11))
                    .foregroundStyle(NotchTheme.secondaryText)
                    .lineSpacing(3)
                    .onboardingSupportingMotion(
                        isVisible: supportingContentIsVisible,
                        reduceMotion: reduceMotion
                    )
            }

            OnboardingPermissionRow(
                title: "Accessibility",
                detail: "Capture selected text from the frontmost app",
                symbol: "cursorarrow.rays",
                isGranted: viewModel.accessibilityGranted,
                action: viewModel.hooks.onRequestAccessibility
            )
            .onboardingSupportingMotion(
                isVisible: supportingContentIsVisible,
                reduceMotion: reduceMotion
            )

            OnboardingPermissionRow(
                title: "Screen Recording",
                detail: "Optional · only needed for region capture",
                symbol: "viewfinder",
                isGranted: viewModel.screenRecordingGranted,
                action: viewModel.hooks.onRequestScreenRecording
            )
            .onboardingSupportingMotion(
                isVisible: supportingContentIsVisible,
                reduceMotion: reduceMotion
            )

            NotchToggle(title: "Launch at login", isOn: $viewModel.launchAtLogin)
                .onboardingSupportingMotion(
                    isVisible: supportingContentIsVisible,
                    reduceMotion: reduceMotion
                )
            Spacer()
        }
        .padding(.horizontal, 28)
    }

    private var onboardingFooter: some View {
        HStack {
            if viewModel.onboardingPage > 0 {
                Button("Back") { move(to: viewModel.onboardingPage - 1) }
                    .buttonStyle(CompactTextButtonStyle())
                    .notchHitTarget(Rectangle())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(NotchTheme.secondaryText)
            } else {
                Color.clear.frame(width: 34, height: 1)
            }

            Spacer()

            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { page in
                    Capsule()
                        .fill(page == viewModel.onboardingPage ? NotchTheme.mint : Color.white.opacity(0.14))
                        .frame(width: 14, height: 5)
                        .scaleEffect(x: page == viewModel.onboardingPage ? 1 : 5 / 14)
                }
            }
            .transaction { transaction in
                if reduceMotion { transaction.animation = nil }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Step \(viewModel.onboardingPage + 1) of 3")

            Spacer()

            Button(viewModel.onboardingPage == 2 ? "Start capturing" : "Continue") {
                if viewModel.onboardingPage == 2 {
                    viewModel.openExpanded()
                } else {
                    move(to: viewModel.onboardingPage + 1)
                }
            }
            .buttonStyle(MintButtonStyle())
            .notchHitTarget(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .padding(.horizontal, 16)
        .frame(height: 58)
        .background(NotchTheme.ink)
        .overlay(alignment: .top) {
            Rectangle().fill(NotchTheme.hairline).frame(height: 1)
        }
    }

    private func move(to page: Int) {
        navigationDirection = page >= viewModel.onboardingPage ? 1 : -1
        hideSupportingContent()
        if reduceMotion {
            withAnimation(NotchMotion.reducedMotion) {
                viewModel.onboardingPage = page
            }
        } else {
            withAnimation(NotchMotion.onboarding) {
                viewModel.onboardingPage = page
            }
        }
        stageSupportingContent()
    }

    private var pageTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(x: 12 * navigationDirection)),
            removal: .opacity.combined(with: .offset(x: -12 * navigationDirection))
        )
    }

    private func hideSupportingContent() {
        stagingGeneration &+= 1
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            supportingContentIsVisible = false
        }
    }

    private func stageSupportingContent() {
        hideSupportingContent()
        let generation = stagingGeneration
        Task { @MainActor in
            await Task.yield()
            guard generation == stagingGeneration else { return }
            supportingContentIsVisible = true
        }
    }
}

private struct OnboardingSupportingMotion: ViewModifier {
    let isVisible: Bool
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: reduceMotion || isVisible ? 0 : 3)
            .animation(
                reduceMotion
                    ? NotchMotion.reducedMotion
                    : NotchMotion.onboarding.delay(NotchMotion.stagingDelay),
                value: isVisible
            )
    }
}

private extension View {
    func onboardingSupportingMotion(isVisible: Bool, reduceMotion: Bool) -> some View {
        modifier(OnboardingSupportingMotion(isVisible: isVisible, reduceMotion: reduceMotion))
    }
}

private struct MiniNotch: View {
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Capsule()
                .fill(.black)
                .frame(width: 88, height: 30)
                .overlay(alignment: .bottom) {
                    Capsule().fill(color).frame(width: 24, height: 1).padding(.bottom, 3)
                }
            Text(label)
                .font(.system(size: 8, weight: .bold))
                .tracking(0.7)
                .foregroundStyle(NotchTheme.tertiaryText)
        }
    }
}

private struct OnboardingPermissionRow: View {
    let title: String
    let detail: String
    let symbol: String
    let isGranted: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isGranted ? NotchTheme.mint : Color.white.opacity(0.66))
                .frame(width: 32, height: 32)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 11, weight: .semibold))
                Text(detail)
                    .font(.system(size: 9.5))
                    .foregroundStyle(NotchTheme.secondaryText)
            }
            Spacer()
            if isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(NotchTheme.mint)
                    .accessibilityLabel("Allowed")
            } else {
                Button("Allow", action: action)
                    .buttonStyle(MintButtonStyle())
                    .notchHitTarget(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.035))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(NotchTheme.hairline, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title), \(isGranted ? "allowed" : "not allowed")")
    }
}
