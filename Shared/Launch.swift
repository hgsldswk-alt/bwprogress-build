import Foundation

enum Launch {
    static let freePeriod = false
    static let arguments = ProcessInfo.processInfo.arguments
    static let testing = arguments.contains("-ui-testing")
    static let proID = "com.hgsldswk.bodyweightprogression.pro"
    static let trialID = "com.hgsldswk.bodyweightprogression.trial"

    static func isFree(arguments: [String]) -> Bool {
        freePeriod && !arguments.contains { ["-paid-mode", "-paywall", "-expired"].contains($0) }
    }
    static var isFree: Bool { isFree(arguments: arguments) }
}

struct Entitlement: Codable, Equatable, Sendable {
    var firstOpen = Date()
    var proStartedAt: Date?
    var trialClaimedAt: Date?
    var trialRevoked: Bool?
    var purchasedPro = false

    var trialStart: Date { proStartedAt ?? firstOpen }
    var trialEnd: Date { trialStart.addingTimeInterval(30 * 86_400) }

    func hasPro(at date: Date, free: Bool = Launch.isFree) -> Bool {
        free || purchasedPro || (trialRevoked != true && date >= trialStart && date < trialEnd)
    }

    mutating func verifyTrial(originalDate: Date) {
        let start = min(trialStart, originalDate)
        proStartedAt = start
        trialClaimedAt = originalDate
    }
}
