//
//  OnboardingContainerView.swift
//  Focus IOS
//

import SwiftUI

struct OnboardingContainerView: View {
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var notificationManager: NotificationManager

    @State private var currentStep = 0
    private let totalSteps = 4

    var body: some View {
        ZStack(alignment: .top) {
            Color.appBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                headerBar

                Group {
                    switch currentStep {
                    case 0:
                        OnboardingIntroStep(onContinue: nextStep)
                    case 1:
                        OnboardingWelcomeStep(onContinue: nextStep)
                    case 2:
                        OnboardingNotificationsStep(onContinue: nextStep)
                    case 3:
                        OnboardingCompletionStep(onFinish: completeOnboarding)
                    default:
                        EmptyView()
                    }
                }
                .id(currentStep)
                .transition(slideTransition)
                .animation(AppStyle.Anim.modeSwitch, value: currentStep)
            }
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        VStack(spacing: AppStyle.Spacing.compact) {
            HStack {
                if currentStep > 0 {
                    Button {
                        withAnimation(AppStyle.Anim.modeSwitch) {
                            currentStep -= 1
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.inter(size: 16, weight: .semiBold))
                            .foregroundColor(.appText)
                            .frame(width: AppStyle.Layout.touchTarget,
                                   height: AppStyle.Layout.touchTarget)
                    }
                } else {
                    Spacer()
                        .frame(width: AppStyle.Layout.touchTarget,
                               height: AppStyle.Layout.touchTarget)
                }
                Spacer()
            }
            .padding(.horizontal, AppStyle.Spacing.section)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.focusBlue.opacity(0.15))
                        .frame(height: 4)

                    Capsule()
                        .fill(Color.focusBlue)
                        .frame(
                            width: geo.size.width * CGFloat(currentStep + 1) / CGFloat(totalSteps),
                            height: 4
                        )
                        .animation(AppStyle.Anim.modeSwitch, value: currentStep)
                }
            }
            .frame(height: 4)
            .padding(.horizontal, AppStyle.Spacing.section)
        }
        .padding(.top, AppStyle.Spacing.compact)
    }

    // MARK: - Transitions

    private var slideTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }

    // MARK: - Navigation

    private func nextStep() {
        withAnimation(AppStyle.Anim.modeSwitch) {
            currentStep = min(currentStep + 1, totalSteps - 1)
        }
    }

    private func completeOnboarding() {
        _Concurrency.Task { @MainActor in
            do {
                try await authService.markOnboardingCompleted()
            } catch {
                // User can tap again
            }
        }
    }
}
