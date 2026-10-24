import Foundation
import StoreKit

enum StoreError: LocalizedError {
    case productUnavailable
    case failedVerification

    var errorDescription: String? {
        switch self {
        case .productUnavailable: return "Whistler Pro isn't available from the App Store right now. Try again in a moment."
        case .failedVerification: return "The App Store couldn't verify that purchase."
        }
    }
}

/// Live StoreKit 2 implementation.
@MainActor
final class StoreKitSource: EntitlementSource {
    private var product: Product?
    private var updatesTask: Task<Void, Never>?

    private func loadProduct() async throws -> Product {
        if let product { return product }
        let products = try await Product.products(for: [ProProduct.id])
        guard let pro = products.first(where: { $0.id == ProProduct.id }) else {
            throw StoreError.productUnavailable
        }
        product = pro
        return pro
    }

    func loadDisplayPrice() async throws -> String? {
        try await loadProduct().displayPrice
    }

    func currentEntitlements() async -> Set<String> {
        var ids: Set<String> = []
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            // Revoked (refunded / Family Sharing removed) transactions don't count.
            guard transaction.revocationDate == nil else { continue }
            if ProProduct.all.contains(transaction.productID) {
                ids.insert(transaction.productID)
            }
        }
        return ids
    }

    func purchasePro() async throws -> PurchaseOutcome {
        let pro = try await loadProduct()
        let result = try await pro.purchase()
        switch result {
        case .success(let verification):
            let transaction = try Self.verified(verification)
            await transaction.finish()
            return .purchased
        case .pending:
            return .pending
        case .userCancelled:
            return .cancelled
        @unknown default:
            return .cancelled
        }
    }

    func restore() async throws {
        try await AppStore.sync()
    }

    func startListening(onChange: @escaping @MainActor () async -> Void) {
        guard updatesTask == nil else { return }
        updatesTask = Task.detached(priority: .background) {
            for await result in Transaction.updates {
                // Unverified updates are ignored; verified ones (including
                // revocations and offer-code redemptions) are finished.
                if case .verified(let transaction) = result {
                    await transaction.finish()
                }
                await onChange()
            }
        }
    }

    func stopListening() {
        updatesTask?.cancel()
        updatesTask = nil
    }

    nonisolated private static func verified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let value): return value
        case .unverified: throw StoreError.failedVerification
        }
    }
}
