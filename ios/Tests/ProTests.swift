import XCTest
@testable import Whistler

@MainActor
final class FakeEntitlementSource: EntitlementSource {
    var entitled: Set<String> = []
    var price: String? = "$2.99"
    var priceError: Error?
    var purchaseOutcome: PurchaseOutcome = .purchased
    var purchaseError: Error?
    var restoreGrants = false
    private(set) var listening = false
    private(set) var purchaseCalls = 0
    private(set) var restoreCalls = 0
    private var onChange: (@MainActor () async -> Void)?

    func loadDisplayPrice() async throws -> String? {
        if let priceError { throw priceError }
        return price
    }

    func currentEntitlements() async -> Set<String> { entitled }

    func purchasePro() async throws -> PurchaseOutcome {
        purchaseCalls += 1
        if let purchaseError { throw purchaseError }
        if purchaseOutcome == .purchased { entitled.insert(ProProduct.id) }
        return purchaseOutcome
    }

    func restore() async throws {
        restoreCalls += 1
        if restoreGrants { entitled.insert(ProProduct.id) }
    }

    func startListening(onChange: @escaping @MainActor () async -> Void) {
        listening = true
        self.onChange = onChange
    }

    func stopListening() { listening = false }

    /// Simulates a Transaction.updates delivery (refund, offer code, other device).
    func pushUpdate() async { await onChange?() }
}

@MainActor
final class ProStatusTests: XCTestCase {
    func testStartsFreeWithNoEntitlement() async {
        let fake = FakeEntitlementSource()
        let pro = ProStatus(source: fake)
        await pro.start()
        XCTAssertFalse(pro.isPro)
        XCTAssertTrue(pro.hasLoaded)
        XCTAssertTrue(fake.listening, "updates listener must start at launch")
        XCTAssertEqual(pro.displayPrice, "$2.99")
    }

    func testExistingEntitlementUnlocksAtLaunch() async {
        let fake = FakeEntitlementSource()
        fake.entitled = [ProProduct.id]
        let pro = ProStatus(source: fake)
        await pro.start()
        XCTAssertTrue(pro.isPro)
    }

    func testUnrelatedProductDoesNotUnlock() async {
        let fake = FakeEntitlementSource()
        fake.entitled = ["com.nightmoose.whistler.other"]
        let pro = ProStatus(source: fake)
        await pro.start()
        XCTAssertFalse(pro.isPro)
    }

    func testPurchaseUnlocks() async {
        let fake = FakeEntitlementSource()
        let pro = ProStatus(source: fake)
        await pro.start()
        await pro.purchase()
        XCTAssertTrue(pro.isPro)
        XCTAssertFalse(pro.isPurchasing)
        XCTAssertEqual(fake.purchaseCalls, 1)
    }

    func testCancelledPurchaseStaysFree() async {
        let fake = FakeEntitlementSource()
        fake.purchaseOutcome = .cancelled
        let pro = ProStatus(source: fake)
        await pro.start()
        await pro.purchase()
        XCTAssertFalse(pro.isPro)
        XCTAssertNil(pro.message)
    }

    func testPendingPurchaseStaysFreeWithMessage() async {
        let fake = FakeEntitlementSource()
        fake.purchaseOutcome = .pending
        let pro = ProStatus(source: fake)
        await pro.start()
        await pro.purchase()
        XCTAssertFalse(pro.isPro)
        XCTAssertNotNil(pro.message)
    }

    func testFailedVerificationStaysFree() async {
        let fake = FakeEntitlementSource()
        fake.purchaseError = StoreError.failedVerification
        let pro = ProStatus(source: fake)
        await pro.start()
        await pro.purchase()
        XCTAssertFalse(pro.isPro)
        XCTAssertEqual(pro.message, StoreError.failedVerification.errorDescription)
    }

    func testRestoreUnlocks() async {
        let fake = FakeEntitlementSource()
        fake.restoreGrants = true
        let pro = ProStatus(source: fake)
        await pro.start()
        await pro.restore()
        XCTAssertTrue(pro.isPro)
        XCTAssertEqual(fake.restoreCalls, 1)
    }

    func testRestoreWithNothingStaysFree() async {
        let fake = FakeEntitlementSource()
        let pro = ProStatus(source: fake)
        await pro.start()
        await pro.restore()
        XCTAssertFalse(pro.isPro)
        XCTAssertNotNil(pro.message)
    }

    func testOfferCodeRedemptionViaUpdatesUnlocks() async {
        let fake = FakeEntitlementSource()
        let pro = ProStatus(source: fake)
        await pro.start()
        fake.entitled = [ProProduct.id]
        await fake.pushUpdate()
        XCTAssertTrue(pro.isPro)
    }

    func testRevocationViaUpdatesRelocks() async {
        let fake = FakeEntitlementSource()
        fake.entitled = [ProProduct.id]
        let pro = ProStatus(source: fake)
        await pro.start()
        XCTAssertTrue(pro.isPro)
        fake.entitled = []
        await fake.pushUpdate()
        XCTAssertFalse(pro.isPro)
    }

    func testPriceFailureLeavesPriceNil() async {
        let fake = FakeEntitlementSource()
        fake.priceError = StoreError.productUnavailable
        let pro = ProStatus(source: fake)
        await pro.start()
        XCTAssertNil(pro.displayPrice)
    }
}

final class GateTests: XCTestCase {
    func testFreeTierLocksEveryProFeature() {
        let gate = Gate(isPro: false)
        for feature in ProFeature.allCases {
            XCTAssertFalse(gate.allows(feature), "\(feature) should be locked on free")
        }
    }

    func testProUnlocksEveryFeature() {
        let gate = Gate(isPro: true)
        for feature in ProFeature.allCases {
            XCTAssertTrue(gate.allows(feature))
        }
    }

    func testWhistleModeIsFree() {
        XCTAssertTrue(Gate(isPro: false).allows(mode: .whistle))
        XCTAssertNil(SourceMode.whistle.proFeature)
    }

    func testHumAndAnyNeedPro() {
        XCTAssertFalse(Gate(isPro: false).allows(mode: .hum))
        XCTAssertFalse(Gate(isPro: false).allows(mode: .any))
        XCTAssertTrue(Gate(isPro: true).allows(mode: .hum))
        XCTAssertTrue(Gate(isPro: true).allows(mode: .any))
        XCTAssertEqual(SourceMode.hum.proFeature, .humMode)
        XCTAssertEqual(SourceMode.any.proFeature, .anyMode)
    }

    func testProductIDMatchesAppStoreConnect() {
        XCTAssertEqual(ProProduct.id, "com.nightmoose.whistler.pro")
    }
}

final class RecordingCapTests: XCTestCase {
    func testFreeCapIsAboutFifteenSeconds() {
        XCTAssertEqual(RecordingCap.freeLimit, 15)
    }

    func testFreeStopsAtCap() {
        XCTAssertFalse(RecordingCap.shouldStop(elapsed: 14.9, isPro: false))
        XCTAssertTrue(RecordingCap.shouldStop(elapsed: 15, isPro: false))
        XCTAssertTrue(RecordingCap.shouldStop(elapsed: 40, isPro: false))
    }

    func testProNeverStops() {
        XCTAssertFalse(RecordingCap.shouldStop(elapsed: 15, isPro: true))
        XCTAssertFalse(RecordingCap.shouldStop(elapsed: 3600, isPro: true))
        XCTAssertNil(RecordingCap.remaining(elapsed: 100, isPro: true))
    }

    func testRemaining() {
        XCTAssertEqual(RecordingCap.remaining(elapsed: 5, isPro: false), 10)
        XCTAssertEqual(RecordingCap.remaining(elapsed: 20, isPro: false), 0)
    }
}

@MainActor
final class SessionGatingTests: XCTestCase {
    func testCapStopsRecordingAndShowsPaywall() {
        let session = WhistleSession()
        session.isPro = false
        session.isRecording = true
        session.tick(elapsed: 10)
        XCTAssertTrue(session.isRecording)
        XCTAssertNil(session.paywallTrigger)
        session.tick(elapsed: 15.05)
        XCTAssertFalse(session.isRecording)
        XCTAssertEqual(session.elapsed, RecordingCap.freeLimit)
        XCTAssertEqual(session.paywallTrigger?.reason, .recordingCap)
    }

    func testProRecordingIsNotCapped() {
        let session = WhistleSession()
        session.isPro = true
        session.isRecording = true
        session.tick(elapsed: 120)
        XCTAssertTrue(session.isRecording)
        XCTAssertNil(session.paywallTrigger)
        XCTAssertEqual(session.elapsed, 120)
        session.isRecording = false
    }

    func testLockedModeOpensPaywallInsteadOfSwitching() {
        let session = WhistleSession()
        session.isPro = false
        XCTAssertFalse(session.select(mode: .hum))
        XCTAssertEqual(session.mode, .whistle)
        XCTAssertEqual(session.paywallTrigger?.reason, .feature(.humMode))
    }

    func testProCanSwitchModes() {
        let session = WhistleSession()
        session.isPro = true
        XCTAssertTrue(session.select(mode: .any))
        XCTAssertEqual(session.mode, .any)
        XCTAssertNil(session.paywallTrigger)
    }

    func testLosingProFallsBackToWhistle() {
        let session = WhistleSession()
        session.isPro = true
        session.select(mode: .hum)
        session.isPro = false
        XCTAssertEqual(session.mode, .whistle)
    }
}
