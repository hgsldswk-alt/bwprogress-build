import SwiftUI

struct PaywallView: View {
    @EnvironmentObject private var store: AppStoreModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PageHeader(title: L.t("shop.title"), subtitle: nil) {
                    Action(title: L.t("close"), id: "paywall.close") { dismiss() }
                }
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(["sheets", "custom", "widget", "card"], id: \.self) { item in
                        Label(L.t("shop.feature.\(item)"), systemImage: "checkmark")
                            .foregroundStyle(Palette.action).font(.subheadline.weight(.semibold))
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .panel()

                VStack(alignment: .leading, spacing: 6) {
                    Text(L.t("shop.trial.title")).font(.headline)
                    Text(L.t("shop.trial.body")).font(.subheadline).foregroundStyle(Palette.muted)
                    if store.rights.purchasedPro {
                        Text(L.t("shop.owned")).font(.subheadline.weight(.semibold))
                    } else if store.pro {
                        Text(L.f("shop.ends", store.rights.trialEnd.formatted(date: .abbreviated, time: .omitted)))
                            .font(.subheadline.weight(.semibold))
                    } else {
                        Text(L.t("shop.expired")).font(.subheadline.weight(.semibold))
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .panel()
                if !store.rights.purchasedPro {
                    Action(title: store.proPrice.map { L.f("shop.buy.price", $0) } ?? L.t("shop.buy"),
                           id: "paywall.buy", style: .prominent) {
                        Task { await store.buy(Launch.proID) }
                    }
                    .disabled(store.shopBusy)
                    if store.rights.trialClaimedAt == nil && store.pro {
                        Action(title: L.t("shop.claim"), id: "paywall.trial", style: .outline) {
                            Task { await store.buy(Launch.trialID) }
                        }
                        .disabled(store.shopBusy)
                    }
                }
                Action(title: L.t("shop.restore"), id: "paywall.restore") {
                    Task { await store.restore() }
                }
                .disabled(store.shopBusy)
                if store.shopBusy { ProgressView().accessibilityLabel(L.t("loading")) }
                if let message = store.shopMessage {
                    Text(L.t(message)).font(.subheadline).accessibilityIdentifier("paywall.status")
                }
            }
            .page()
        }
        .task { await store.loadProducts() }
    }
}
