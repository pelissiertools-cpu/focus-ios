//
//  OnboardingCompletionStep.swift
//  Focus IOS
//

import SwiftUI

struct OnboardingCompletionStep: View {
    @EnvironmentObject var authService: AuthService
    let onFinish: () -> Void

    @State private var showCheckmark = false
    @State private var showText = false
    @State private var showButton = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Animated checkmark
            ZStack {
                Circle()
                    .fill(Color.todayBadge)
                    .frame(width: 120, height: 120)
                    .scaleEffect(showCheckmark ? 1 : 0.5)
                    .opacity(showCheckmark ? 1 : 0)

                Image(systemName: "checkmark")
                    .font(.system(size: 50, weight: .bold))
                    .foregroundColor(.focusBlue)
                    .scaleEffect(showCheckmark ? 1 : 0.3)
                    .opacity(showCheckmark ? 1 : 0)
            }
            .animation(AppStyle.Anim.modeSwitch, value: showCheckmark)
            .padding(.bottom, AppStyle.Spacing.expanded)

            Text("Welcome to Focus")
                .font(AppStyle.Typography.pageTitle)
                .tracking(AppStyle.Typography.pageTitleTracking)
                .foregroundColor(.appText)
                .opacity(showText ? 1 : 0)
                .offset(y: showText ? 0 : 10)
                .animation(AppStyle.Anim.expand.delay(0.2), value: showText)
                .padding(.bottom, AppStyle.Spacing.compact)

            Text("We are happy to have you on board.")
                .font(.inter(.body))
                .foregroundColor(.secondary)
                .opacity(showText ? 1 : 0)
                .offset(y: showText ? 0 : 10)
                .animation(AppStyle.Anim.expand.delay(0.35), value: showText)

            Spacer()
            Spacer()

            Button(action: onFinish) {
                HStack {
                    if authService.isLoading {
                        ProgressView()
                            .tint(.focusBlue)
                    } else {
                        Text("Start planning")
                            .font(.helveticaNeue(size: 15.22, weight: .medium))
                            .tracking(-0.158)
                            .foregroundColor(.focusBlue)
                    }
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.helveticaNeue(size: 17.3, weight: .medium))
                        .foregroundColor(.focusBlue)
                        .frame(width: AppStyle.Layout.pillButton, alignment: .center)
                }
                .padding(AppStyle.Spacing.section)
                .frame(maxWidth: .infinity, minHeight: AppStyle.Layout.fab)
                .background(Color.todayBadge, in: RoundedRectangle(cornerRadius: AppStyle.CornerRadius.card))
                .cardBorderOverlay()
                .cardShadow()
            }
            .buttonStyle(.plain)
            .disabled(authService.isLoading)
            .opacity(showButton ? 1 : 0)
            .offset(y: showButton ? 0 : 10)
            .animation(AppStyle.Anim.expand.delay(0.5), value: showButton)
            .padding(.horizontal, AppStyle.Spacing.page)
            .padding(.bottom, 40)
        }
        .onAppear {
            showCheckmark = true
            showText = true
            showButton = true
        }
    }
}
