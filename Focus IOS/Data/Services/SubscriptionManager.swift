//
//  SubscriptionManager.swift
//  Focus IOS
//

import Foundation
import Combine
import StoreKit

enum SubscriptionTier: String {
    case none
    case monthly
    case annual
}

@MainActor
class SubscriptionManager: ObservableObject {
    static let shared = SubscriptionManager()

    /// Set to `true` to enable paywall gates. Set to `false` to bypass all gates.
    nonisolated static let paywallEnabled = false

    nonisolated static let monthlyProductId = "focus_monthly_pro"
    nonisolated static let annualProductId = "focus_annual_pro"
    private nonisolated static let productIds: Set<String> = [monthlyProductId, annualProductId]

    @Published var isSubscribed = false
    @Published var currentTier: SubscriptionTier = .none
    @Published var products: [Product] = []
    @Published var isLoading = false
    @Published var isLoadingProducts = true
    @Published var errorMessage: String?
    @Published var expirationDate: Date?

    private var transactionListener: _Concurrency.Task<Void, Never>?

    private init() {
        transactionListener = listenForTransactions()
        _Concurrency.Task { @MainActor in
            await loadProducts()
            await updateSubscriptionStatus()
        }
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Transaction Listener

    private func listenForTransactions() -> _Concurrency.Task<Void, Never> {
        _Concurrency.Task.detached { [weak self] in
            for await result in Transaction.updates {
                guard let self = self else { return }
                if let transaction = try? result.payloadValue {
                    await transaction.finish()
                    await self.updateSubscriptionStatus()
                }
            }
        }
    }

    // MARK: - Load Products

    func loadProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            let storeProducts = try await Product.products(for: Self.productIds)
            self.products = storeProducts.sorted { $0.price < $1.price }
        } catch {
            self.errorMessage = "Failed to load products."
        }
    }

    // MARK: - Purchase

    func purchase(_ product: Product) async throws {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            let transaction = try verification.payloadValue
            await transaction.finish()
            await updateSubscriptionStatus()

        case .userCancelled:
            break

        case .pending:
            errorMessage = "Purchase is pending approval."

        @unknown default:
            errorMessage = "An unknown error occurred."
        }
    }

    // MARK: - Restore Purchases

    func restorePurchases() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await AppStore.sync()
            await updateSubscriptionStatus()
            if !isSubscribed {
                errorMessage = "No active subscription found."
            }
        } catch {
            errorMessage = "Failed to restore purchases."
        }
    }

    // MARK: - Subscription Status

    func updateSubscriptionStatus() async {
        var foundActive = false

        for await result in Transaction.currentEntitlements {
            if let transaction = try? result.payloadValue {
                if transaction.productID == Self.monthlyProductId ||
                    transaction.productID == Self.annualProductId {
                    if transaction.revocationDate == nil {
                        foundActive = true
                        currentTier = transaction.productID == Self.monthlyProductId ? .monthly : .annual
                        expirationDate = transaction.expirationDate
                    }
                }
            }
        }

        isSubscribed = Self.paywallEnabled ? foundActive : true
        if !foundActive && Self.paywallEnabled {
            currentTier = .none
            expirationDate = nil
        }
    }

    // MARK: - Helpers

    var monthlyProduct: Product? {
        products.first { $0.id == Self.monthlyProductId }
    }

    var annualProduct: Product? {
        products.first { $0.id == Self.annualProductId }
    }

    var formattedExpirationDate: String? {
        guard let date = expirationDate else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }

    var annualSavingsText: String? {
        guard let monthly = monthlyProduct,
              let annual = annualProduct else { return nil }
        let monthlyYearly = monthly.price * 12
        let savings = ((monthlyYearly - annual.price) / monthlyYearly) * 100
        return "Save \(NSDecimalNumber(decimal: savings).intValue)%"
    }

    func openManageSubscriptions() async {
        if let windowScene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
            try? await AppStore.showManageSubscriptions(in: windowScene)
        }
    }
}
