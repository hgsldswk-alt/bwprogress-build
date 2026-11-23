import Foundation

struct WidgetSnapshot: Codable, Sendable {
    static let group = "group.com.hgsldswk.bodyweightprogression"
    static let kind = "BodyweightProgressionToday"
    static let filename = "today.json"
    static let destination = URL(string: "bwprogression://today")!

    var count: Int
    var goal: Int
    var weekEnd: Date?
    var pinned: Movement?
    var last: Int?
    var afterMidnight: Int?
    var nextMidnight: Date?
    var expires: Date?

    init(state: TrainingState, entitlement: Entitlement, now: Date, zone: TimeZone) {
        count = state.weeklyCount(at: now, zone: zone)
        goal = state.goal
        weekEnd = TrainingState.week(at: now, zone: zone)?.end
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        nextMidnight = calendar.dateInterval(of: .day, for: now)?.end
        if entitlement.hasPro(at: now) {
            pinned = state.activeSheet.currentMoves.first { $0.id == state.pinID }
                ?? state.activeSheet.currentMoves.first
            if let pinned {
                last = state.last(pinned, excluding: state.currentSession(at: now, zone: zone)?.id)?.sets.last?.value
                afterMidnight = state.last(pinned, excluding: nil)?.sets.last?.value
            }
            expires = entitlement.purchasedPro || Launch.isFree ? nil : entitlement.trialEnd
        }
    }

    func count(at date: Date) -> Int { weekEnd.map { date < $0 ? count : 0 } ?? count }
    func movement(at date: Date) -> Movement? {
        if let expires, date >= expires { return nil }
        return pinned
    }
    func value(at date: Date) -> Int? {
        if let nextMidnight, date >= nextMidnight { return afterMidnight }
        return last
    }
}
