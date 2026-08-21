import SwiftUI

struct OnboardingView: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var navigationDirection: CGFloat = 1

    var body: some View {
        VStack(spacing: 0) {
            onboardingTopBand

            Group {
                switch viewModel.onboardingStep {
                case .capture:
                    OnboardingCapturePage()
                case .organize:
                    OnboardingOrganizePage()
                case .music:
                    OnboardingMusicPage()
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

    private var onboardingTopBand: some View {
        HStack {
            Spacer()

            HStack(spacing: 5) {
                ForEach(AppViewModel.OnboardingStep.allCases) { step in
                    Capsule()
                        .fill(
                            step == viewModel.onboardingStep
                                ? NotchTheme.primaryAccent
                                : Color.white.opacity(0.14)
                        )
                        .frame(width: step == viewModel.onboardingStep ? 14 : 5, height: 5)
                }
            }
            .animation(reduceMotion ? nil : NotchMotion.filter, value: viewModel.onboardingStep)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "Step \(viewModel.onboardingStep.number) of \(AppViewModel.OnboardingStep.allCases.count)"
            )
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(NotchTheme.ink)
        .overlay(alignment: .bottom) {
            Rectangle().fill(NotchTheme.hairline).frame(height: 1)
        }
    }

    private var onboardingFooter: some View {
        HStack {
            if !viewModel.onboardingStep.isFirst {
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

            Button(viewModel.onboardingStep.isFinal ? "Open inbox" : "Continue") {
                if viewModel.onboardingStep.isFinal {
                    viewModel.finishOnboarding()
                } else {
                    moveForward()
                }
            }
            .buttonStyle(PrimaryButtonStyle())
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
