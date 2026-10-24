import StoreKit
import SwiftUI

struct PaywallView: View {
    @Environment(ProStatus.self) private var pro
    @Environment(\.dismiss) private var dismiss
    var trigger: PaywallTrigger
    @State private var redeeming = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("WHISTLER PRO")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .tracking(3)
                        .foregroundStyle(Theme.brass)
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.muted)
                            .padding(8)
                            .background(Theme.ink2, in: Circle())
                    }
                    .accessibilityLabel("Close")
                }
                Text(headline)
                    .font(.system(size: 30, weight: .medium, design: .serif))
                    .foregroundStyle(Theme.paper)
                    .fixedSize(horizontal: false, vertical: true)
                Text("One purchase, yours to keep. No subscription.")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.muted)

                VStack(alignment: .leading, spacing: 14) {
                    ForEach(ProFeature.allCases) { feature in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: feature.symbol)
                                .frame(width: 24)
                                .foregroundStyle(Theme.brass)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(feature.title)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(Theme.paper)
                                Text(feature.detail)
                                    .font(.system(size: 13))
                                    .foregroundStyle(Theme.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(16)
                .background(Theme.ink2, in: RoundedRectangle(cornerRadius: 20))

                if pro.isPro {
                    Label("Pro is unlocked. Thank you!", systemImage: "checkmark.seal.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Theme.brass)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                } else {
                    Button {
                        Task { await pro.purchase() }
                    } label: {
                        Group {
                            if pro.isPurchasing {
                                ProgressView().tint(Theme.ink)
                            } else if let price = pro.displayPrice {
                                Text("Unlock Pro · \(price)")
                            } else {
                                Text("Unlock Pro")
                            }
                        }
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.brass, in: Capsule())
                        .foregroundStyle(Theme.ink)
                    }
                    .buttonStyle(.plain)
                    .disabled(pro.isPurchasing || pro.displayPrice == nil)
                    .accessibilityIdentifier("buyPro")

                    if pro.displayPrice == nil {
                        Text("Loading price from the App Store…")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.muted)
                            .frame(maxWidth: .infinity)
                    }
                }

                HStack(spacing: 20) {
                    Button("Restore Purchases") {
                        Task { await pro.restore() }
                    }
                    Button("Redeem Code") {
                        redeeming = true
                    }
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.brass)
                .frame(maxWidth: .infinity)

                if let message = pro.message {
                    Text(message)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(24)
        }
        .background(Theme.ink.ignoresSafeArea())
        .offerCodeRedemption(isPresented: $redeeming) { _ in
            Task { await pro.redeemFinished() }
        }
        .task {
            if pro.displayPrice == nil { await pro.loadPrice() }
        }
    }

    private var headline: String {
        switch trigger.reason {
        case .recordingCap:
            return "Free takes stop at \(Int(RecordingCap.freeLimit)) seconds. Go Pro to keep whistling."
        case .feature(let feature):
            return "\(feature.title) is part of Whistler Pro."
        case .browse:
            return "Get everything Whistler can do."
        }
    }
}

/// Small lock badge shown on gated controls.
struct LockBadge: View {
    var body: some View {
        Image(systemName: "lock.fill")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Theme.ink)
            .padding(4)
            .background(Theme.brass, in: Circle())
            .accessibilityLabel("Pro")
    }
}

/// Locked placeholder for a gated section: the feature stays visible but tapping opens the paywall.
struct LockedPanel: View {
    var feature: ProFeature
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                LockBadge()
                VStack(alignment: .leading, spacing: 2) {
                    Text(feature.title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.inkText)
                    Text("Unlock with Whistler Pro")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.inkText.opacity(0.6))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(Theme.inkText.opacity(0.5))
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.paper.opacity(0.85), in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("locked-\(feature.rawValue)")
    }
}
