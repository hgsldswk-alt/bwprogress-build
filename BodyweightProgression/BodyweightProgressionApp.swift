import SwiftUI
import StoreKit

@main
struct BodyweightProgressionApp: App {
    @StateObject private var store = AppStoreModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.light)
                .tint(Palette.action)
        }
    }
}

enum MainTab: String, CaseIterable {
    case today, history, settings

    var icon: String {
        switch self {
        case .today: return "list.bullet.rectangle"
        case .history: return "clock"
        case .settings: return "gearshape"
        }
    }
}

enum Modal: Identifiable {
    case number(Movement, UUID?)
    case progression(MovementGroup)
    case history(Session)
    case card(Milestone)
    case importSheet
    case paywall
    case editor(Bool)

    var id: String {
        switch self {
        case .number(let movement, _): return "number.\(movement.id)"
        case .progression(let group): return "progression.\(group.id)"
        case .history(let session): return "history.\(session.id)"
        case .card(let milestone): return "card.\(milestone.id)"
        case .importSheet: return "import"
        case .paywall: return "paywall"
        case .editor(let new): return new ? "new" : "edit"
        }
    }

    var isNumber: Bool {
        if case .number = self { return true }
        return false
    }
}

struct RootView: View {
    @EnvironmentObject private var store: AppStoreModel
    @Environment(\.scenePhase) private var phase
    @Environment(\.requestReview) private var requestReview
    @State private var tab: MainTab = .today
    @State private var modal: Modal?
    @State private var reviewRequested = false
    @State private var lastZone = TimeZone.current
    private let clock = Timer.publish(every: 15, on: .main, in: .common).autoconnect()

    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0" }
    private var canAsk: Bool {
        store.ready && tab == .today && modal == nil && phase == .active && store.dataMessage == nil
            && store.guided == nil
            && store.state.reviewEligible && store.state.reviewVersion != version
    }

    var body: some View {
        Group {
            if store.ready {
                selectedPage
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        VStack(spacing: 0) {
                            if tab == .today { RestBar(timer: store.rest) }
                            tabBar
                        }
                    }
            } else {
                ProgressView().accessibilityLabel(L.t("loading"))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(Palette.ink)
        .background(Palette.paper.ignoresSafeArea())
        .sheet(item: $modal, onDismiss: { store.tick() }) { presented in
            modalView(presented)
                .foregroundStyle(Palette.ink)
                .presentationBackground(Palette.paper)
                .presentationDragIndicator(.visible)
        }
        .task {
            await store.start()
            if Launch.testing && Launch.arguments.contains("-paywall") { modal = .paywall }
        }
        .task(id: canAsk) {
            guard canAsk else { return }
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled, canAsk else { return }
            store.change { $0.reviewVersion = version }
            if Launch.testing { reviewRequested = true } else { requestReview() }
        }
        .onChange(of: phase) { _, new in
            if new == .active {
                store.tick(keepSession: modal?.isNumber == true)
                Task { await store.rest.refreshAuthorization() }
            }
        }
        .onReceive(clock) { _ in
            store.tick(keepSession: modal?.isNumber == true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
            let zone = TimeZone.current
            guard lastZone != zone else { return }
            lastZone = zone
            store.tick(keepSession: modal?.isNumber == true, refreshWidget: true)
        }
        .onOpenURL { url in
            guard url.scheme == WidgetSnapshot.destination.scheme else { return }
            modal = nil
            tab = .today
        }
    }

    @ViewBuilder private var selectedPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let message = store.dataMessage {
                    HStack {
                        Text(L.t(message)).foregroundStyle(.red)
                        if message == "error.save" {
                            Action(title: L.t("try.again"), id: "data.retry") { store.retrySave() }
                        }
                    }
                }
                switch tab {
                case .today:
                    TodayView(open: { modal = $0 })
                    if reviewRequested {
                        Text(L.t("review.requested")).accessibilityIdentifier("review.requested")
                    }
                case .history:
                    HistoryView(open: { modal = $0 })
                case .settings:
                    SettingsView(open: { modal = $0 })
                }
            }
            .page()
        }
        .id(tab)
    }

    private var tabBar: some View {
        HStack(spacing: 5) {
            ForEach(MainTab.allCases, id: \.self) { item in
                Button {
                    tab = item
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: item.icon).accessibilityHidden(true)
                        Text(L.t("tab.\(item.rawValue)")).font(.caption.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .foregroundStyle(tab == item ? Palette.action : Palette.muted)
                    .background(tab == item ? Palette.tint : Color.clear, in: RoundedRectangle(cornerRadius: 9))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("tab.\(item.rawValue)")
                .accessibilityAddTraits(tab == item ? .isSelected : [])
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 5)
        .background(Palette.paper)
        .overlay(alignment: .top) { Divider().overlay(Palette.line).allowsHitTesting(false) }
    }

    @ViewBuilder private func modalView(_ presented: Modal) -> some View {
        switch presented {
        case .number(let move, let sessionID):
            NumberView(movement: move, sessionID: sessionID)
                .presentationDetents([.medium, .large])
        case .progression(let group):
            ProgressionView(groupID: group.id)
        case .history(let session):
            SessionView(sessionID: session.id)
        case .card(let milestone):
            CardView(milestone: milestone)
        case .importSheet:
            ImportView {
                modal = nil
                tab = .today
            }
        case .paywall:
            PaywallView()
        case .editor(let new):
            SheetEditor(isNew: new)
        }
    }
}
