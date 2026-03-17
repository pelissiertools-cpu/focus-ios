//
//  PaywallView.swift
//  Focus IOS
//

import SwiftUI
import StoreKit

struct PaywallView: View {
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @Environment(\.dismiss) private var dismiss
    let onContinue: (() -> Void)?
    let showSkip: Bool

    @State private var selectedProduct: Product?
    @State private var selectedFallback: String = SubscriptionManager.annualProductId

    init(onContinue: (() -> Void)? = nil, showSkip: Bool = false) {
        self.onContinue = onContinue
        self.showSkip = showSkip
    }

    /// True when presented as a sheet (not during onboarding)
    private var isSheet: Bool { onContinue == nil }

    var body: some View {
        if isSheet {
            sheetPaywall
        } else {
            onboardingPaywall
        }
    }

    // MARK: - Sheet Paywall (feature gate)

    private var sheetPaywall: some View {
        VStack(spacing: 0) {
            // Title bar
            ZStack {
                Text("Pro Plan")
                    .font(.inter(.headline, weight: .semiBold))
                    .foregroundColor(.appText)

                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.secondary)
                            .frame(width: 30, height: 30)
                            .background(Color(.systemGray5), in: Circle())
                    }
                }
            }
            .padding(.horizontal, AppStyle.Spacing.page)
            .padding(.top, AppStyle.Spacing.section)
            .padding(.bottom, AppStyle.Spacing.compact)

            ScrollView {
                VStack(spacing: 0) {
                    // Feature highlights
                    sheetFeatureHighlights
                        .padding(.top, AppStyle.Spacing.section)
                        .padding(.bottom, AppStyle.Spacing.expanded)

                    // Pricing cards (side by side)
                    pricingCards
                        .padding(.horizontal, AppStyle.Spacing.page)
                        .padding(.bottom, AppStyle.Spacing.section)

                    // Refresh subscription
                    VStack(spacing: AppStyle.Spacing.tiny) {
                        Text("Account didn't upgrade?")
                            .font(.inter(.caption))
                            .foregroundColor(.secondary)
                        Button("Refresh Subscription") {
                            _Concurrency.Task { @MainActor in
                                await subscriptionManager.restorePurchases()
                            }
                        }
                        .font(.inter(.caption, weight: .semiBold))
                        .foregroundColor(.focusBlue)
                    }
                    .padding(.bottom, AppStyle.Spacing.expanded)
                }
            }

            Spacer()

            // Continue button
            Button {
                if let selected = selectedProduct {
                    purchaseSelected(selected)
                } else {
                    purchaseFallback()
                }
            } label: {
                Group {
                    if subscriptionManager.isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Continue")
                            .font(.helveticaNeue(size: 15.22, weight: .medium))
                            .tracking(-0.158)
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, minHeight: AppStyle.Layout.fab)
                .background(Color.focusBlue, in: RoundedRectangle(cornerRadius: AppStyle.CornerRadius.card))
            }
            .buttonStyle(.plain)
            .disabled(subscriptionManager.isLoading)
            .padding(.horizontal, AppStyle.Spacing.page)

            Text("Recurring billing. Cancel anytime.")
                .font(.inter(.caption2))
                .foregroundColor(.secondary)
                .padding(.top, AppStyle.Spacing.compact)
                .padding(.bottom, 40)
        }
        .background(Color.appBackground)
        .onAppear { syncSelectedProduct() }
        .onChange(of: subscriptionManager.products) { _, _ in syncSelectedProduct() }
        .alert("Error", isPresented: .constant(subscriptionManager.errorMessage != nil)) {
            Button("OK") { subscriptionManager.errorMessage = nil }
        } message: {
            Text(subscriptionManager.errorMessage ?? "")
        }
    }

    // MARK: - Onboarding Paywall (full comparison)

    private var onboardingPaywall: some View {
        VStack(spacing: 0) {
            // Top bar
            HStack {
                Spacer()
                Button("Restore") {
                    _Concurrency.Task { @MainActor in
                        await subscriptionManager.restorePurchases()
                    }
                }
                .font(.inter(.subheadline))
                .foregroundColor(.secondary)
            }
            .padding(.horizontal, AppStyle.Spacing.page)
            .frame(height: AppStyle.Layout.touchTarget)

            ScrollView {
                VStack(spacing: 0) {
                    Text("Focus Pro")
                        .font(.helveticaNeue(size: 26.14, weight: .medium))
                        .tracking(AppStyle.Typography.pageTitleTracking)
                        .foregroundColor(.appText)
                        .padding(.top, AppStyle.Spacing.compact)
                        .padding(.bottom, AppStyle.Spacing.compact)

                    Text("Unlock your full productivity potential")
                        .font(.inter(.body))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, AppStyle.Spacing.expanded)
                        .padding(.bottom, AppStyle.Spacing.section)

                    // Free vs Pro comparison table
                    comparisonTable
                        .padding(.horizontal, AppStyle.Spacing.page)
                        .padding(.bottom, AppStyle.Spacing.expanded)

                    // Pricing cards (side by side)
                    pricingCards
                        .padding(.horizontal, AppStyle.Spacing.page)
                        .padding(.bottom, AppStyle.Spacing.expanded)

                    // Get Pro button
                    Button {
                        if let selected = selectedProduct {
                            purchaseSelected(selected)
                        } else {
                            purchaseFallback()
                        }
                    } label: {
                        Group {
                            if subscriptionManager.isLoading {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("Get Pro")
                                    .font(.helveticaNeue(size: 15.22, weight: .medium))
                                    .tracking(-0.158)
                            }
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, minHeight: AppStyle.Layout.fab)
                        .background(Color.focusBlue, in: RoundedRectangle(cornerRadius: AppStyle.CornerRadius.card))
                    }
                    .buttonStyle(.plain)
                    .disabled(subscriptionManager.isLoading)
                    .padding(.horizontal, AppStyle.Spacing.page)

                    // Continue for free
                    if showSkip {
                        Button {
                            onContinue?()
                        } label: {
                            Text("Continue for free")
                                .font(.helveticaNeue(size: 15.22, weight: .medium))
                                .tracking(-0.158)
                                .foregroundColor(.focusBlue)
                                .frame(maxWidth: .infinity, minHeight: AppStyle.Layout.fab)
                                .background(Color.clear, in: RoundedRectangle(cornerRadius: AppStyle.CornerRadius.card))
                                .overlay(
                                    RoundedRectangle(cornerRadius: AppStyle.CornerRadius.card)
                                        .stroke(Color.focusBlue, lineWidth: AppStyle.Border.thin)
                                )
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, AppStyle.Spacing.page)
                        .padding(.top, AppStyle.Spacing.compact)
                    }

                    // Legal links
                    HStack(spacing: AppStyle.Spacing.section) {
                        Link("Terms of Use", destination: URL(string: "https://focusapp.com/terms")!)
                        Link("Privacy Policy", destination: URL(string: "https://focusapp.com/privacy")!)
                    }
                    .font(.inter(.caption2))
                    .foregroundColor(.secondary)
                    .padding(.top, AppStyle.Spacing.compact)
                    .padding(.bottom, 40)
                }
            }
        }
        .background(Color.appBackground)
        .onAppear { syncSelectedProduct() }
        .onChange(of: subscriptionManager.products) { _, _ in syncSelectedProduct() }
        .alert("Error", isPresented: .constant(subscriptionManager.errorMessage != nil)) {
            Button("OK") { subscriptionManager.errorMessage = nil }
        } message: {
            Text(subscriptionManager.errorMessage ?? "")
        }
    }

    // MARK: - Sheet Feature Highlights

    private var sheetFeatureHighlights: some View {
        let highlights = [
            ("checklist", "Unlimited lists"),
            ("folder", "Unlimited projects"),
            ("sparkles", "Smart AI task breakdown"),
            ("person.2", "Share lists and projects")
        ]

        return VStack(spacing: AppStyle.Spacing.section) {
            ForEach(highlights, id: \.1) { icon, text in
                HStack(spacing: AppStyle.Spacing.comfortable) {
                    Image(systemName: icon)
                        .font(.system(size: 18))
                        .foregroundColor(.focusBlue)
                        .frame(width: 28)

                    Text(text)
                        .font(.inter(.body))
                        .foregroundColor(.appText)

                    Spacer()
                }
            }
        }
        .padding(.horizontal, AppStyle.Spacing.page + AppStyle.Spacing.section)
    }

    // MARK: - Comparison Table

    private var comparisonTable: some View {
        VStack(spacing: 0) {
            // Header row
            HStack {
                Text("Features")
                    .font(.inter(.subheadline, weight: .semiBold))
                    .foregroundColor(.appText)
                Spacer()
                Text("Free")
                    .font(.inter(.subheadline, weight: .semiBold))
                    .foregroundColor(.secondary)
                    .frame(width: 50)
                Text("Pro")
                    .font(.inter(.subheadline, weight: .semiBold))
                    .foregroundColor(.focusBlue)
                    .frame(width: 50)
            }
            .padding(.horizontal, AppStyle.Spacing.section)
            .padding(.vertical, AppStyle.Spacing.content)

            Divider()

            comparisonRow("Unlimited tasks management", free: true, pro: true)
            comparisonRow("Tasks scheduling", free: true, pro: true)
            comparisonRow("Up to 3 quick lists", free: true, pro: true)
            comparisonRow("Unlimited lists", free: false, pro: true)
            comparisonRow("Unlimited projects", free: false, pro: true)
            comparisonRow("Smart AI task breakdown", free: false, pro: true)
            comparisonRow("Share lists and projects", free: false, pro: true)
        }
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: AppStyle.CornerRadius.card))
        .cardBorderOverlay()
        .cardShadow()
    }

    private func comparisonRow(_ feature: String, free: Bool, pro: Bool) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(feature)
                    .font(.inter(.subheadline))
                    .foregroundColor(.appText)
                Spacer()
                Group {
                    if free {
                        Image(systemName: "checkmark")
                            .foregroundColor(.secondary)
                    } else {
                        Image(systemName: "minus")
                            .foregroundStyle(.quaternary)
                    }
                }
                .font(.inter(.subheadline, weight: .semiBold))
                .frame(width: 50)

                Group {
                    if pro {
                        Image(systemName: "checkmark")
                            .foregroundColor(.focusBlue)
                    } else {
                        Image(systemName: "minus")
                            .foregroundStyle(.quaternary)
                    }
                }
                .font(.inter(.subheadline, weight: .semiBold))
                .frame(width: 50)
            }
            .padding(.horizontal, AppStyle.Spacing.section)
            .padding(.vertical, AppStyle.Spacing.content)

            Divider()
                .padding(.leading, AppStyle.Spacing.section)
        }
    }

    // MARK: - Pricing Cards (shared)

    private var pricingCards: some View {
        HStack(spacing: AppStyle.Spacing.comfortable) {
            if !subscriptionManager.products.isEmpty {
                if let annual = subscriptionManager.annualProduct {
                    storeKitPricingCard(product: annual, isAnnual: true)
                }
                if let monthly = subscriptionManager.monthlyProduct {
                    storeKitPricingCard(product: monthly, isAnnual: false)
                }
            } else if subscriptionManager.isLoadingProducts {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                fallbackPricingCard(
                    id: SubscriptionManager.annualProductId,
                    title: "Pay Yearly",
                    price: "$50",
                    period: "/year",
                    perMonth: "($4.17/mo)",
                    savings: "Save 65%"
                )
                fallbackPricingCard(
                    id: SubscriptionManager.monthlyProductId,
                    title: "Pay Monthly",
                    price: "$12",
                    period: "/month",
                    perMonth: "($12/mo)",
                    savings: nil
                )
            }
        }
    }

    private func storeKitPricingCard(product: Product, isAnnual: Bool) -> some View {
        let isSelected = selectedProduct?.id == product.id

        return Button {
            selectedProduct = product
        } label: {
            VStack(spacing: AppStyle.Spacing.tiny) {
                if isAnnual, let savings = subscriptionManager.annualSavingsText {
                    Text(savings)
                        .font(.inter(.caption2, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, AppStyle.Spacing.content)
                        .padding(.vertical, AppStyle.Spacing.micro)
                        .background(Color.focusBlue, in: Capsule())
                } else {
                    Text(" ")
                        .font(.inter(.caption2, weight: .bold))
                        .padding(.vertical, AppStyle.Spacing.micro)
                }

                Text(isAnnual ? "Pay Yearly" : "Pay Monthly")
                    .font(.inter(.subheadline, weight: .semiBold))
                    .foregroundColor(.appText)

                Text(product.displayPrice)
                    .font(.helveticaNeue(size: 24, weight: .medium))
                    .foregroundColor(.appText)

                Text(isAnnual ? "/year" : "/month")
                    .font(.inter(.caption))
                    .foregroundColor(.secondary)

                if isAnnual {
                    let monthly = product.price / 12
                    Text("($\(NSDecimalNumber(decimal: monthly).doubleValue, specifier: "%.2f")/mo)")
                        .font(.inter(.caption))
                        .foregroundColor(.secondary)
                } else {
                    Text(" ")
                        .font(.inter(.caption))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppStyle.Spacing.section)
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: AppStyle.CornerRadius.card))
            .overlay(
                RoundedRectangle(cornerRadius: AppStyle.CornerRadius.card)
                    .stroke(isSelected ? Color.focusBlue : Color.cardBorder,
                            lineWidth: isSelected ? 2 : AppStyle.Border.thin)
            )
            .cardShadow()
        }
        .buttonStyle(.plain)
    }

    private func fallbackPricingCard(id: String, title: String, price: String, period: String, perMonth: String, savings: String?) -> some View {
        let isSelected = selectedFallback == id

        return Button {
            selectedFallback = id
        } label: {
            VStack(spacing: AppStyle.Spacing.tiny) {
                if let savings {
                    Text(savings)
                        .font(.inter(.caption2, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, AppStyle.Spacing.content)
                        .padding(.vertical, AppStyle.Spacing.micro)
                        .background(Color.focusBlue, in: Capsule())
                } else {
                    Text(" ")
                        .font(.inter(.caption2, weight: .bold))
                        .padding(.vertical, AppStyle.Spacing.micro)
                }

                Text(title)
                    .font(.inter(.subheadline, weight: .semiBold))
                    .foregroundColor(.appText)

                Text(price)
                    .font(.helveticaNeue(size: 24, weight: .medium))
                    .foregroundColor(.appText)

                Text(period)
                    .font(.inter(.caption))
                    .foregroundColor(.secondary)

                Text(perMonth)
                    .font(.inter(.caption))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppStyle.Spacing.section)
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: AppStyle.CornerRadius.card))
            .overlay(
                RoundedRectangle(cornerRadius: AppStyle.CornerRadius.card)
                    .stroke(isSelected ? Color.focusBlue : Color.cardBorder,
                            lineWidth: isSelected ? 2 : AppStyle.Border.thin)
            )
            .cardShadow()
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func syncSelectedProduct() {
        if selectedProduct == nil {
            selectedProduct = subscriptionManager.annualProduct
                ?? subscriptionManager.products.first
        }
    }

    private func purchaseSelected(_ product: Product) {
        _Concurrency.Task { @MainActor in
            do {
                try await subscriptionManager.purchase(product)
                if subscriptionManager.isSubscribed {
                    onContinue?()
                    if isSheet { dismiss() }
                }
            } catch {
                // Error handled via subscriptionManager.errorMessage
            }
        }
    }

    private func purchaseFallback() {
        _Concurrency.Task { @MainActor in
            await subscriptionManager.loadProducts()

            let targetId = selectedFallback
            if let product = subscriptionManager.products.first(where: { $0.id == targetId }) {
                selectedProduct = product
                purchaseSelected(product)
            } else {
                subscriptionManager.errorMessage = "Unable to connect to the App Store. Please try again later."
            }
        }
    }
}
