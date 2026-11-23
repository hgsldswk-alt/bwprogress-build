import Foundation

struct GuidedWorkout: Equatable, Sendable {
    let sheetID: String
    let day: LocalDay
    let movements: [Movement]
    private(set) var index = 0

    init?(sheet: TrainingSheet, day: LocalDay) {
        let movements = sheet.currentMoves
        guard !movements.isEmpty else { return nil }
        self.sheetID = sheet.id
        self.day = day
        self.movements = movements
    }

    var movement: Movement? { movements.indices.contains(index) ? movements[index] : nil }
    var hasNext: Bool { index + 1 < movements.count }

    mutating func advance() {
        if movement != nil { index += 1 }
    }
}
