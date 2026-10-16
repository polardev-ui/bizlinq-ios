import Foundation
import StoreKit
import UIKit

/// Poster plans. Browsing is free; posting requires an active subscription.
/// Entitlements come from StoreKit 2, so refunds, renewals, and billing
/// retries are handled by the App Store, not by us.
struct SubscriptionPlan: Identifiable, Hashable {
    let id: String
    let name: String
    let price: String
    let cadence: String
    let blurb: String
    let badge: String?
    let systemImage: String

    static let monthly = SubscriptionPlan(
        id: "bizlinq.poster.monthly",
        name: "Poster Monthly",
        price: "$10",
        cadence: "per month",
        blurb: "Post unlimited meetings. Cancel anytime.",
        badge: "Most popular",
        systemImage: "calendar.badge.clock"
    )

    static let annual = SubscriptionPlan(
        id: "bizlinq.poster.annual",
        name: "Poster Annual",
        price: "$99",
        cadence: "per year",
        blurb: "Same unlimited posting. About 2 months free vs monthly.",
        badge: "Best value",
        systemImage: "crown.fill"
    )

    static let all: [SubscriptionPlan] = [.monthly, .annual]
}

@MainActor
final class SubscriptionManager: ObservableObject {
    private enum Keys {
        static let entitledProduct = "bizlinq.entitledProduct"
        static let expiry = "bizlinq.subscriptionExpiry"
    }

    @Published var products: [Product] = []
    @Published var isPurchasing: Bool = false
    @Published var storeError: String?
    /// Product IDs currently eligible for the 14-day free trial.
    /// Determined by the App Store (one trial per subscription group).
    @Published var trialEligibleIDs: Set<String> = []
    /// Last known-good entitlement, cached so posting still works offline.
    /// Revalidated against the App Store on every launch and purchase.
    @Published private(set) var entitledProductID: String?
    /// Next renewal date of the active subscription, if known.
    @Published private(set) var subscriptionExpiry: Date?

    init() {
        entitledProductID = UserDefaults.standard.string(forKey: Keys.entitledProduct)
        let stamp = UserDefaults.standard.double(forKey: Keys.expiry)
        if stamp > 0 {
            subscriptionExpiry = Date(timeIntervalSince1970: stamp)
        }
        Task { await listenForTransactions() }
        Task { await loadProducts() }
    }

    var isPosterActive: Bool {
        entitledProductID != nil
    }

    var activePlan: SubscriptionPlan? {
        SubscriptionPlan.all.first { $0.id == entitledProductID }
    }

    func loadProducts() async {
        do {
            products = try await Product.products(for: SubscriptionPlan.all.map { $0.id })
        } catch {
            products = []
        }
        await refreshTrialEligibility()
        await refreshEntitlements()
    }

    func refreshTrialEligibility() async {
        var eligible: Set<String> = []
        for product in products {
            if await product.subscription?.isEligibleForIntroOffer == true {
                eligible.insert(product.id)
            }
        }
        trialEligibleIDs = eligible
    }

    func isTrialEligible(_ plan: SubscriptionPlan) -> Bool {
        trialEligibleIDs.contains(plan.id)
    }

    func purchase(_ plan: SubscriptionPlan) async {
        storeError = nil
        if products.isEmpty {
            await loadProducts()
        }
        guard let product = products.first(where: { $0.id == plan.id }) else {
            #if targetEnvironment(simulator)
            storeError = "No App Store products found. In Xcode: BizLinq scheme → Edit Scheme → Run → Options → StoreKit Configuration → BizLinq.storekit. (On devices/TestFlight, products come from App Store Connect.)"
            #else
            storeError = "The App Store is unavailable right now. Please try again later."
            #endif
            return
        }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    await transaction.finish()
                    await refreshEntitlements()
                case .unverified:
                    storeError = "The purchase could not be verified."
                }
            case .userCancelled:
                break
            case .pending:
                storeError = "The purchase is pending approval."
            @unknown default:
                break
            }
        } catch {
            storeError = error.localizedDescription
        }
    }

    func refreshEntitlements() async {
        var entitled: String?
        var expiry: Date?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard transaction.revocationDate == nil else { continue }
            guard SubscriptionPlan.all.map({ $0.id }).contains(transaction.productID) else { continue }
            if let expires = transaction.expirationDate, expires <= Date() { continue }
            entitled = transaction.productID
            expiry = transaction.expirationDate
            break
        }
        entitledProductID = entitled
        subscriptionExpiry = expiry
        UserDefaults.standard.set(entitled, forKey: Keys.entitledProduct)
        if let expiry {
            UserDefaults.standard.set(expiry.timeIntervalSince1970, forKey: Keys.expiry)
        } else {
            UserDefaults.standard.removeObject(forKey: Keys.expiry)
        }
    }

    func restore() async {
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            try await AppStore.sync()
            await refreshEntitlements()
        } catch {
            storeError = error.localizedDescription
        }
    }

    /// Cancellation happens in the App Store; we just deep-link there.
    func openManageSubscriptions() {
        if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
            UIApplication.shared.open(url)
        }
    }

    private func listenForTransactions() async {
        for await result in Transaction.updates {
            if case .verified(let transaction) = result {
                await refreshEntitlements()
                await transaction.finish()
            }
        }
    }
}
