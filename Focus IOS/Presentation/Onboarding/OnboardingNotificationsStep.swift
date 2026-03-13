//
//  OnboardingNotificationsStep.swift
//  Focus IOS
//

import SwiftUI

struct OnboardingNotificationsStep: View {
    @EnvironmentObject var notificationManager: NotificationManager
    let onContinue: () -> Void

    @State private var hasRequested = false

    var body: some View {
        VStack(spacing: 0) {
            // Skip button
            HStack {
                Spacer()
                if !hasRequested {
                    Button("Skip") {
                        onContinue()
                    }
                    .font(.inter(.body))
                    .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, AppStyle.Spacing.page)
            .frame(height: AppStyle.Layout.touchTarget)

            Spacer()

            Image(systemName: "bell.badge.fill")
                .font(.system(size: 56))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.red, Color(.systemGray5))
                .padding(.bottom, AppStyle.Spacing.expanded)

            Text("Never miss a task")
                .font(AppStyle.Typography.pageTitle)
                .tracking(AppStyle.Typography.pageTitleTracking)
                .foregroundColor(.appText)
                .padding(.bottom, AppStyle.Spacing.comfortable)

            Text("Get reminders for your scheduled tasks\nso nothing slips through the cracks.")
                .font(.inter(.body))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppStyle.Spacing.expanded)
                .padding(.bottom, AppStyle.Spacing.expanded)

            // Notification preview card
            notificationPreview
                .padding(.horizontal, AppStyle.Spacing.page)

            Spacer()
            Spacer()

            if !hasRequested {
                Button(action: requestNotifications) {
                    Text("Enable Notifications")
                        .font(.helveticaNeue(size: 15.22, weight: .medium))
                        .tracking(-0.158)
                        .foregroundColor(.focusBlue)
                        .frame(maxWidth: .infinity, minHeight: AppStyle.Layout.fab)
                        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: AppStyle.CornerRadius.card))
                        .cardBorderOverlay()
                        .cardShadow()
                }
                .buttonStyle(.plain)
                .padding(.horizontal, AppStyle.Spacing.page)
                .padding(.bottom, 40)
            } else {
                Button(action: onContinue) {
                    Text("Start planning")
                        .font(.helveticaNeue(size: 15.22, weight: .medium))
                        .tracking(-0.158)
                        .foregroundColor(.focusBlue)
                        .frame(maxWidth: .infinity, minHeight: AppStyle.Layout.fab)
                        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: AppStyle.CornerRadius.card))
                        .cardBorderOverlay()
                        .cardShadow()
                }
                .buttonStyle(.plain)
                .padding(.horizontal, AppStyle.Spacing.page)
                .padding(.bottom, 40)
            }
        }
    }

    // MARK: - Notification Preview

    private var notificationPreview: some View {
        HStack(spacing: AppStyle.Spacing.comfortable) {
            RoundedRectangle(cornerRadius: AppStyle.CornerRadius.iconBadge)
                .fill(Color.black)
                .frame(width: 38, height: 38)
                .overlay(
                    Image(systemName: "scope")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                )

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("Focus")
                        .font(.inter(.caption, weight: .semiBold))
                    Spacer()
                    Text("now")
                        .font(.inter(.caption2))
                        .foregroundColor(.secondary)
                }
                Text("Time to focus — You have 4 tasks due today.")
                    .font(.inter(.subheadline))
                    .foregroundColor(.appText)
                    .lineLimit(2)
            }
        }
        .padding(AppStyle.Spacing.content)
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppStyle.CornerRadius.card))
        .cardBorderOverlay()
        .cardShadow()
    }

    // MARK: - Actions

    private func requestNotifications() {
        notificationManager.isEnabled = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(AppStyle.Anim.toggle) {
            hasRequested = true
        }
    }
}
