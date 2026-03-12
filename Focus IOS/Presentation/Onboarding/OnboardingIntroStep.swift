//
//  OnboardingIntroStep.swift
//  Focus IOS
//

import SwiftUI

struct OnboardingIntroStep: View {
    let onContinue: () -> Void

    @State private var showTitle = false
    @State private var showSubtitle = false
    @State private var showButton = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "scope")
                .font(.system(size: 64, weight: .medium))
                .foregroundColor(.focusBlue)
                .opacity(showTitle ? 1 : 0)
                .scaleEffect(showTitle ? 1 : 0.6)
                .animation(AppStyle.Anim.modeSwitch, value: showTitle)
                .padding(.bottom, AppStyle.Spacing.expanded)

            Text("We're happy to\nsee you here")
                .font(AppStyle.Typography.pageTitle)
                .tracking(AppStyle.Typography.pageTitleTracking)
                .foregroundColor(.appText)
                .multilineTextAlignment(.center)
                .opacity(showTitle ? 1 : 0)
                .offset(y: showTitle ? 0 : 10)
                .animation(AppStyle.Anim.expand.delay(0.15), value: showTitle)
                .padding(.bottom, AppStyle.Spacing.comfortable)

            Text("Let's get you set up in just a minute.")
                .font(.inter(.body))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .opacity(showSubtitle ? 1 : 0)
                .offset(y: showSubtitle ? 0 : 8)
                .animation(AppStyle.Anim.expand.delay(0.3), value: showSubtitle)

            Spacer()
            Spacer()

            Button(action: onContinue) {
                Text("Continue")
                    .font(.inter(.body, weight: .semiBold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Color.focusBlue)
                    .clipShape(RoundedRectangle(cornerRadius: AppStyle.CornerRadius.button))
            }
            .opacity(showButton ? 1 : 0)
            .animation(AppStyle.Anim.expand.delay(0.5), value: showButton)
            .padding(.bottom, 40)
        }
        .padding(.horizontal, AppStyle.Spacing.page)
        .onAppear {
            showTitle = true
            showSubtitle = true
            showButton = true
        }
    }
}
