import Foundation
import StoreKit
import SwiftUI
import WidgetKit

@MainActor
final class AppStoreModel: ObservableObject {
    @Published private(set) var state = TrainingState()
    @Published private(set) var rights = Entitlement()
    @Published private(set) var ready = false
    @Published private(set) var now = Date()
    @Published private(set) var proPrice: String?
    @Published private(set) var shopBusy = false
    @Published var shopMessage: String?
    @Published var dataMessage: String?
    @Published private(set) var guided: GuidedWorkout?

    let rest = RestTimer()

    private var products: [String: Product] = [:]
    private var updates: Task<Void, Never>?
    private var diskHealthy = true
    private let io = DispatchQueue(label: "BodyweightProgression.files")
    private let testing = Launch.testing
    private var testDateOffset: TimeInterval = 0

    var zone: TimeZone { .current }
    var pro: Bool { rights.hasPro(at: now) }
    var sheet: TrainingSheet { state.activeSheet }
    var current: Session? { state.currentSession(at: now, zone: zone) }

    func start() async {
        guard !ready else { return }
        let testing = self.testing
        let reset = testing && Launch.arguments.contains("-reset")
        let result = await Task.detached(priority: .userInitiated) {
            let disk = Result { try LocalFiles.read(testing: testing, reset: reset) }
            let rights = Result { () -> Entitlement in
                guard !testing else { return Entitlement() }
                if let entitlement = try EntitlementCache.load() { return entitlement }
                let entitlement = Entitlement()
                try EntitlementCache.save(entitlement)
                return entitlement
            }
            return (disk, rights)
        }.value
        switch result.0 {
        case .success(let file): state = file.training
        case .failure:
            diskHealthy = false
            dataMessage = "error.load"
        }
        switch result.1 {
        case .success(let rights): self.rights = rights
        case .failure: shopMessage = "shop.unavailable"
        }
        if testing {
            if Launch.arguments.contains("-expired") { rights.firstOpen = Date().addingTimeInterval(-31 * 86_400) }
            if Launch.arguments.contains("-purchased") { rights.purchasedPro = true }
            if Launch.arguments.contains("-demo") { seedDemo() }
        }
        ready = true
        tick()
        publishWidget()
        guard !testing else { return }
        updates = Task { [weak self] in
            for await result in StoreKit.Transaction.updates {
                guard let self else { return }
                if case .verified(let transaction) = result {
                    await self.apply(transaction)
                    self.shopMessage = transaction.revocationDate == nil ? "shop.success" : "shop.revoked"
                } else {
                    self.shopMessage = "shop.unverified"
                }
            }
        }
        Task { await refreshRights() }
    }

    func tick(keepSession: Bool = false, refreshWidget: Bool = false) {
        guard ready else { return }
        let oldDate = now
        now = Date().addingTimeInterval(testDateOffset)
        if !keepSession {
            change { $0.roll(to: now, zone: zone) }
            if let guided, guided.sheetID != state.activeSheetID || guided.day.key != LocalDay(at: now, zone: zone).key {
                exitGuided()
            }
        }
        if refreshWidget || LocalDay(at: oldDate, zone: zone) != LocalDay(at: now, zone: zone)
            || rights.hasPro(at: oldDate) != pro {
            publishWidget()
        }
    }

    func advanceTestDay() {
        guard testing else { return }
        testDateOffset += 86_400
        tick()
    }

    @discardableResult
    func change(_ update: (inout TrainingState) -> Void) -> Bool {
        guard ready, diskHealthy else { return false }
        var next = state
        update(&next)
        guard next != state else { return false }
        state = next
        persist(next)
        return true
    }

    func retrySave() {
        persist(state)
    }

    private func persist(_ training: TrainingState) {
        let snapshot = DiskState(training: training)
        let testing = self.testing
        let (rights, now, zone) = (self.rights, self.now, self.zone)
        io.async { [weak self] in
            do {
                try LocalFiles.save(snapshot, testing: testing)
                if !testing {
                    let widget = WidgetSnapshot(state: training, entitlement: rights, now: now, zone: zone)
                    if (try? LocalFiles.publish(widget)) == true {
                        WidgetCenter.shared.reloadTimelines(ofKind: WidgetSnapshot.kind)
                    }
                }
                Task { @MainActor in
                    if self?.dataMessage == "error.save" { self?.dataMessage = nil }
                }
            } catch {
                Task { @MainActor in self?.dataMessage = "error.save" }
            }
        }
    }

    func record(_ value: Int?, movement: Movement, sessionID: UUID?) {
        tick(keepSession: true)
        let (date, zone) = (now, self.zone)
        var recorded = false
        change { draft in
            recorded = draft.record(value, for: movement, at: date, zone: zone, continuing: sessionID)
            draft.roll(to: date, zone: zone)
        }
        if recorded {
            if value != nil { rest.start(seconds: state.restSeconds) } else { rest.skip() }
        }
    }

    func undoRecord() {
        let (date, zone) = (now, self.zone)
        if change({ $0.undoRecord(at: date, zone: zone) }) { rest.skip() }
    }

    func finishSession() {
        tick()
        let (date, zone) = (now, self.zone)
        change { $0.finish(at: date, zone: zone) }
        rest.skip()
    }

    func startGuided() {
        tick()
        let sheet = self.sheet
        let day = LocalDay(at: now, zone: zone)
        guided = GuidedWorkout(sheet: sheet, day: day)
    }

    func advanceGuided() {
        tick()
        guard var workout = guided else { return }
        workout.advance()
        if workout.movement == nil {
            exitGuided()
            finishSession()
        } else {
            guided = workout
        }
    }

    func exitGuided() { guided = nil }

    func activate(_ sheet: TrainingSheet) {
        let wasActive = state.activeSheetID == sheet.id
        change { draft in
            if !draft.sheets.contains(where: { $0.id == sheet.id }) { draft.sheets.append(sheet) }
            if draft.activeSheetID != sheet.id {
                draft.activeSheetID = sheet.id
                draft.undo = nil
            }
        }
        if !wasActive, state.activeSheetID == sheet.id { exitGuided() }
    }

    func updateSheet(_ update: (inout TrainingSheet) -> Void) {
        change { draft in
            guard let index = draft.sheets.firstIndex(where: { $0.id == draft.activeSheetID }) else { return }
            update(&draft.sheets[index])
        }
    }

    private func publishWidget() {
        guard ready, diskHealthy, !testing else { return }
        let (state, rights, now, zone) = (self.state, self.rights, self.now, self.zone)
        io.async {
            let snapshot = WidgetSnapshot(state: state, entitlement: rights, now: now, zone: zone)
            if (try? LocalFiles.publish(snapshot)) == true {
                WidgetCenter.shared.reloadTimelines(ofKind: WidgetSnapshot.kind)
            }
        }
    }

    func loadProducts() async {
        guard !testing, !shopBusy, products.isEmpty else { return }
        shopBusy = true
        defer { shopBusy = false }
        do {
            let items = try await Product.products(for: [Launch.proID, Launch.trialID])
            products = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
            proPrice = products[Launch.proID]?.displayPrice
            if products[Launch.proID] == nil || products[Launch.trialID] == nil { shopMessage = "shop.unavailable" }
        } catch {
            self.shopMessage = "shop.unavailable"
        }
    }

    func buy(_ id: String) async {
        guard !testing, !shopBusy else { return }
        shopMessage = nil
        if products[id] == nil {
            products = [:]
            await loadProducts()
        }
        guard let product = products[id] else { return }
        shopBusy = true
        defer { shopBusy = false }
        do {
            switch try await product.purchase() {
            case .success(.verified(let transaction)):
                await apply(transaction)
                shopMessage = transaction.revocationDate == nil ? "shop.success" : "shop.revoked"
            case .success(.unverified):
                shopMessage = "shop.unverified"
            case .pending:
                shopMessage = "shop.pending"
            case .userCancelled:
                shopMessage = "shop.cancelled"
            @unknown default:
                shopMessage = "shop.unavailable"
            }
        } catch {
            self.shopMessage = "shop.unavailable"
        }
    }

    func restore() async {
        guard !testing, !shopBusy else { return }
        shopBusy = true
        shopMessage = nil
        defer { shopBusy = false }
        do {
            try await AppStore.sync()
            let found = await refreshRights()
            shopMessage = found ? "shop.restored" : "shop.noPurchases"
        } catch {
            self.shopMessage = "shop.unavailable"
        }
    }

    @discardableResult
    private func refreshRights() async -> Bool {
        var found = false
        for id in [Launch.trialID, Launch.proID] {
            if case .verified(let transaction)? = await StoreKit.Transaction.latest(for: id) {
                await apply(transaction, finish: false)
                found = found || transaction.revocationDate == nil
            }
        }
        return found
    }

    private func apply(_ transaction: StoreKit.Transaction, finish: Bool = true) async {
        var next = rights
        switch transaction.productID {
        case Launch.proID:
            next.purchasedPro = transaction.revocationDate == nil
        case Launch.trialID:
            next.verifyTrial(originalDate: transaction.originalPurchaseDate)
            next.trialRevoked = transaction.revocationDate != nil
        default:
            return
        }
        rights = next
        await withCheckedContinuation { continuation in
            io.async { [weak self] in
                do {
                    try EntitlementCache.save(next)
                } catch {
                    Task { @MainActor in self?.shopMessage = "shop.unavailable" }
                }
                continuation.resume()
            }
        }
        publishWidget()
        if finish { await transaction.finish() }
    }

    private func seedDemo() {
        let base = Date()
        var training = TrainingState()
        for offset in [6.0, 4.0, 2.0] {
            let date = base.addingTimeInterval(-offset * 86_400)
            for (index, move) in training.activeSheet.currentMoves.enumerated() {
                training.record([8, 20, 12, 30][index], for: move, at: date, zone: zone)
            }
            training.finish(at: date, zone: zone)
        }
        if let movement = training.activeSheet.currentMoves.first {
            training.toggleMastery(movement, at: base)
        }
        training.reviewVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        state = training
    }
}
