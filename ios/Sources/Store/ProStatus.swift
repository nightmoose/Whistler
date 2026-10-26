import Foundation
import Observation

/// App-wide Pro entitlement. Created once at launch.
@MainActor
@Observable
final class ProStatus {
    private(set) var isPro = false
    private(set) var displayPrice: String?
    private(set) var isPurchasing = false
    private(set) var hasLoaded = false
    var message: String?

    var gate: Gate { Gate(isPro: isPro) }

    @ObservationIgnored private let source: EntitlementSource

    init(source: EntitlementSource) {
        self.source = source
    }

    /// Call once at launch: start the Transaction.updates listener first so
    /// nothing is missed, then read current entitlements and the price.
    func start() async {
        source.startListening { [weak self] in
            await self?.refreshEntitlements()
        }
        await refreshEntitlements()
        await loadPrice()
    }

    func loadPrice() async {
        do {
            displayPrice = try await source.loadDisplayPrice()
        } catch {
            displayPrice = nil
        }
    }

    /// Re-reads entitlements. Revocations drop Pro here because revoked
    /// transactions are no longer in the current-entitlement set.
    func refreshEntitlements() async {
        let ids = await source.currentEntitlements()
        isPro = ids.contains(ProProduct.id)
        hasLoaded = true
    }

    func purchase() async {
        guard !isPurchasing else { return }
        isPurchasing = true
        message = nil
        defer { isPurchasing = false }
        do {
            switch try await source.purchasePro() {
            case .purchased:
                await refreshEntitlements()
            case .pending:
                message = "Purchase pending approval. Pro unlocks as soon as it goes through."
            case .cancelled:
                break
            }
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func restore() async {
        message = nil
        do {
            try await source.restore()
            await refreshEntitlements()
            message = isPro ? "Whistler Pro restored." : "No previous Pro purchase found for this Apple Account."
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Called after the offer-code sheet closes. The redemption itself also
    /// arrives through Transaction.updates.
    func redeemFinished() async {
        await refreshEntitlements()
    }
}
