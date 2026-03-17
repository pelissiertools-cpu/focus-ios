//
//  SubscriptionDetailView.swift
//  Focus IOS
//

import SwiftUI
import StoreKit

struct SubscriptionDetailView: View {
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    @State private var showPaywall = false

    var body: some View {
        ScrollView {
            VStack(spacing: AppStyle.Spacing.page) {
                // Status card
                statusCard

                // Actions
                if subscriptionManager.isSubscribed {
                    Button {
                        _Concurrency.Task { @MainActor in
                            await subscriptionManager.openManageSubscriptions()
                        }
                    } label: {
                        settingsActionRow(
                            icon: "creditcard",
                            title: "Manage Subscription"
                        )
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        showPaywall = true
                    } label: {
                        Text("Upgrade to Pro")
                            .font(.helveticaNeue(size: 15.22, weight: .medium))
                            .tracking(-0.158)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, minHeight: AppStyle.Layout.fab)
                            .background(Color.focusBlue, in: RoundedRectangle(cornerRadius: AppStyle.CornerRadius.card))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, AppStyle.Spacing.section)
                }

                // Restore
                Button {
                    _Concurrency.Task { @MainActor in
                        await subscriptionManager.restorePurchases()
                    }
                } label: {
                    Text("Restore Purchases")
                        .font(.inter(.caption))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.top, AppStyle.Spacing.page)
        }
        .background(Color.appBackground)
        .navigationTitle("Subscription")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .environmentObject(subscriptionManager)
        }
        .alert("Error", isPresented: .constant(subscriptionManager.errorMessage != nil)) {
            Button("OK") { subscriptionManager.errorMessage = nil }
        } message: {
            Text(subscriptionManager.errorMessage ?? "")
        }
    }

    // MARK: - Status Card

    private var statusCard: some View {
        VStack(spacing: AppStyle.Spacing.comfortable) {
            Image(systemName: subscriptionManager.isSubscribed ? "checkmark.seal.fill" : "scope")
                .font(.system(size: 40, weight: .medium))
                .foregroundColor(subscriptionManager.isSubscribed ? .green : .secondary)

            Text(subscriptionManager.isSubscribed ? "Focus Pro" : "Free Plan")
                .font(.helveticaNeue(size: 22, weight: .medium))
                .foregroundColor(.appText)

            if subscriptionManager.isSubscribed {
                VStack(spacing: AppStyle.Spacing.tiny) {
                    Text(subscriptionManager.currentTier == .annual ? "Annual Plan" : "Monthly Plan")
                        .font(.inter(.body))
                        .foregroundColor(.secondary)

                    if let expDate = subscriptionManager.formattedExpirationDate {
                        Text("Renews \(expDate)")
                            .font(.inter(.caption))
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                Text("Upgrade to unlock all features")
                    .font(.inter(.body))
                    .foregroundColor(.secondary)
            }
        }
        .padding(AppStyle.Spacing.expanded)
        .frame(maxWidth: .infinity)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: AppStyle.CornerRadius.card))
        .cardBorderOverlay()
        .cardShadow()
        .padding(.horizontal, AppStyle.Spacing.section)
    }

    // MARK: - Action Row

    private func settingsActionRow(icon: String, title: String) -> some View {
        HStack(spacing: AppStyle.Spacing.comfortable) {
            Image(systemName: icon)
                .font(.inter(.body))
                .foregroundColor(.appText)
                .frame(width: AppStyle.Layout.pillButton)

            Text(title)
                .font(.inter(.body))
                .foregroundColor(.appText)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.inter(.caption, weight: .semiBold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, AppStyle.Spacing.section)
        .padding(.vertical, AppStyle.Spacing.content)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: AppStyle.CornerRadius.card))
        .cardBorderOverlay()
        .cardShadow()
        .padding(.horizontal, AppStyle.Spacing.section)
    }
}
