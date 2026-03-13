//
//  OnboardingWelcomeStep.swift
//  Focus IOS
//

import SwiftUI

struct OnboardingWelcomeStep: View {
    let onContinue: () -> Void

    @State private var showTitle = false
    @State private var visibleItems = 0
    @State private var showButton = false

    private let benefits: [String] = [
        "Gather all your tasks in one place",
        "Categorize everything to stay organized",
        "Schedule tasks so nothing falls through",
        "Build projects to tackle bigger goals",
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Title
            Text("Welcome to Focus")
                .font(.helveticaNeue(size: 26.14, weight: .medium))
                .tracking(AppStyle.Typography.pageTitleTracking)
                .foregroundColor(.appText)
                .opacity(showTitle ? 1 : 0)
                .offset(y: showTitle ? 0 : 10)
                .animation(AppStyle.Anim.expand, value: showTitle)
                .padding(.bottom, AppStyle.Spacing.expanded)

            // Benefits card
            VStack(alignment: .leading, spacing: 0) {
                Text("Focus can help you...")
                    .font(.inter(.subheadline))
                    .foregroundColor(.secondary)
                    .opacity(showTitle ? 1 : 0)
                    .animation(AppStyle.Anim.expand.delay(0.2), value: showTitle)
                    .padding(.bottom, AppStyle.Spacing.section)

                VStack(alignment: .leading, spacing: AppStyle.Spacing.content) {
                    ForEach(Array(benefits.enumerated()), id: \.offset) { index, text in
                        HStack(spacing: AppStyle.Spacing.comfortable) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 22))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(Color.focusBlue, Color.todayBadge)

                            Text(text)
                                .font(.helveticaNeue(size: 15.22))
                                .foregroundColor(.appText)
                        }
                        .opacity(index < visibleItems ? 1 : 0)
                        .offset(y: index < visibleItems ? 0 : 12)
                        .animation(AppStyle.Anim.expand, value: visibleItems)
                    }
                }
            }
            .padding(AppStyle.Spacing.page)
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: AppStyle.CornerRadius.card))
            .cardBorderOverlay()
            .cardShadow()
            .padding(.horizontal, AppStyle.Spacing.page)

            Spacer()

            Button(action: onContinue) {
                Text("Let's go!")
                    .font(.helveticaNeue(size: 15.22, weight: .medium))
                    .tracking(-0.158)
                    .foregroundColor(.focusBlue)
                    .frame(maxWidth: .infinity, minHeight: AppStyle.Layout.fab)
                    .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: AppStyle.CornerRadius.card))
                    .cardBorderOverlay()
                    .cardShadow()
            }
            .buttonStyle(.plain)
            .opacity(showButton ? 1 : 0)
            .offset(y: showButton ? 0 : 10)
            .animation(AppStyle.Anim.expand, value: showButton)
            .padding(.horizontal, AppStyle.Spacing.page)
            .padding(.bottom, 40)
        }
        .onAppear {
            // 1. Title fades in
            showTitle = true

            // 2. Items appear one by one, 0.5s apart, starting after 0.6s
            for i in 0..<benefits.count {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6 + Double(i) * 0.5) {
                    withAnimation(AppStyle.Anim.expand) {
                        visibleItems = i + 1
                    }
                }
            }

            // 3. Button appears after last item (0.6 + 4*0.5 + 0.3 settle)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.9) {
                showButton = true
            }
        }
    }
}
