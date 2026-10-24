import Foundation

enum PurchaseOutcome: Equatable, Sendable {
    case purchased
    case pending
    case cancelled
}

/// Abstracts the App Store so entitlement logic can be tested without StoreKit.
@MainActor
protocol EntitlementSource: AnyObject {
    /// Localized price string from the store, e.g. "$2.99". Never hard-coded.
    func loadDisplayPrice() async throws -> String?
    /// Product IDs the user is currently entitled to (verified, not revoked).
    func currentEntitlements() async -> Set<String>
    /// Buy Pro. Implementations must verify and finish the transaction.
    func purchasePro() async throws -> PurchaseOutcome
    /// Restore Purchases (AppStore.sync()).
    func restore() async throws
    /// Start listening for out-of-app changes: Ask to Buy approvals, refunds and
    /// revocations, purchases on other devices, and offer-code redemptions.
    /// `onChange` is called after each update has been handled.
    func startListening(onChange: @escaping @MainActor () async -> Void)
    func stopListening()
}
