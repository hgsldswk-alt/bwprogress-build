import Foundation

enum Measurement: String, Codable, CaseIterable, Identifiable, Sendable {
    case reps, seconds
    var id: Self { self }
    var maximum: Int { self == .reps ? 999 : 3600 }
    var short: String { L.t(self == .reps ? "unit.reps" : "unit.seconds") }
    var spoken: String { L.t(self == .reps ? "unit.reps.full" : "unit.seconds.full") }

    func format(_ amount: Int) -> String {
        L.f("value.format", amount, short)
    }
}

struct Movement: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var unit: Measurement
    var hint: String = ""

    var title: String { id.hasPrefix("builtin.") ? L.t(name) : name }
    var instruction: String { id.hasPrefix("builtin.") ? L.t(hint) : hint }
}

struct MovementGroup: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var moves: [Movement]
    var currentID: String

    var title: String { id.hasPrefix("builtin.") ? L.t(name) : name }
    var current: Movement? { moves.first { $0.id == currentID } ?? moves.first }
}

struct TrainingSheet: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var groups: [MovementGroup]

    var title: String { id == "starter" && name == "sheet.starter" ? L.t(name) : name }
    var currentMoves: [Movement] { groups.compactMap(\.current) }

    static func starter() -> Self {
        let recipes: [(String, [Measurement])] = [
            ("push", [.reps, .reps, .reps, .reps]),
            ("pull", [.seconds, .reps, .reps, .reps]),
            ("squat", [.reps, .reps, .reps, .reps]),
            ("hold", [.seconds, .seconds, .seconds, .seconds])
        ]
        return Self(id: "starter", name: "sheet.starter", groups: recipes.map { name, units in
            let moves = units.enumerated().map { index, unit in
                let key = "move.\(name).\(index)"
                return Movement(id: "builtin.\(name).\(index)", name: key, unit: unit, hint: "\(key).hint")
            }
            return MovementGroup(id: "builtin.\(name)", name: "group.\(name)", moves: moves, currentID: moves[0].id)
        })
    }
}

struct LocalDay: Codable, Equatable, Hashable, Sendable {
    var key: String
    var zoneID: String

    init(at date: Date, zone: TimeZone) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        key = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        zoneID = zone.identifier
    }

    func label(at date: Date, timeOnly: Bool = false) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: zoneID) ?? .current
        formatter.dateStyle = timeOnly ? .none : .medium
        formatter.timeStyle = timeOnly ? .short : .none
        return formatter.string(from: date)
    }
}

struct TrainingSet: Codable, Equatable, Sendable {
    var value: Int
    var recordedAt: Date
}

struct Entry: Codable, Equatable, Identifiable, Sendable {
    var movement: Movement
    var sets: [TrainingSet]
    var id: String { "\(movement.id):\(movement.unit.rawValue)" }
    var bestSet: TrainingSet? { sets.max { $0.value < $1.value } }

    init(movement: Movement, sets: [TrainingSet]) {
        self.movement = movement
        self.sets = sets
    }

    private enum CodingKeys: String, CodingKey { case movement, sets, value, recordedAt }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        movement = try values.decode(Movement.self, forKey: .movement)
        if let sets = try values.decodeIfPresent([TrainingSet].self, forKey: .sets) {
            self.sets = sets
        } else {
            sets = [TrainingSet(value: try values.decode(Int.self, forKey: .value),
                                recordedAt: try values.decode(Date.self, forKey: .recordedAt))]
        }
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(movement, forKey: .movement)
        try values.encode(sets, forKey: .sets)
    }

    func matches(_ move: Movement) -> Bool {
        movement.id == move.id && movement.unit == move.unit
    }

    func summary(spoken: Bool = false) -> String {
        let separator = spoken ? ", " : " / "
        let values = sets.map { String($0.value) }.joined(separator: separator)
        let unit = spoken ? movement.unit.spoken : movement.unit.short
        return L.f(sets.count == 1 ? "sets.single" : "sets.multiple", sets.count, values, unit)
    }
}

struct Session: Codable, Equatable, Identifiable, Sendable {
    var id: UUID = UUID()
    var sheetID: String
    var sheetName: String
    var startedAt: Date
    var day: LocalDay
    var entries: [Entry] = []
    var finished = false

    var title: String { sheetID == "starter" && sheetName == "sheet.starter" ? L.t(sheetName) : sheetName }

    func entry(for movement: Movement) -> Entry? {
        entries.first { $0.matches(movement) }
    }
}

struct TrainingUndo: Codable, Equatable, Sendable {
    var sessionID: UUID
    var snapshot: Session
    var movementID: String
}

struct Milestone: Codable, Equatable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable { case mastery, week, best, custom }
    var id: String
    var kind: Kind
    var date: Date
    var sheetID: String
    var movement: Movement?
    var target: Int?
    var dismissedOn: String?
    var used = false
    var bestValue: Int?

    var headline: String {
        switch kind {
        case .mastery: return L.t("card.mastery")
        case .week: return L.f("card.week", target ?? 3)
        case .best: return L.t("card.best")
        case .custom: return L.t("card.custom")
        }
    }
}

struct TrainingState: Codable, Equatable, Sendable {
    var sheets = [TrainingSheet.starter()]
    var activeSheetID = "starter"
    var sessions: [Session] = []
    var mastery: Set<String> = []
    var milestones: [Milestone] = []
    var seenMilestones: Set<String> = []
    var goal = 3
    var pinID: String?
    var undo: TrainingUndo?
    var reviewVersion: String?
    private var savedRestSeconds: Int?

    static let restRange = 30...300
    static let defaultRestSeconds = 90
    var restSeconds: Int {
        guard let savedRestSeconds, Self.restRange.contains(savedRestSeconds) else { return Self.defaultRestSeconds }
        return savedRestSeconds
    }

    var activeSheet: TrainingSheet { sheets.first { $0.id == activeSheetID } ?? .starter() }
    var history: [Session] {
        sessions.filter { !$0.entries.isEmpty }.sorted { $0.startedAt > $1.startedAt }
    }
    var reviewEligible: Bool {
        Set(sessions.lazy.filter { !$0.entries.isEmpty }.map(\.day.key)).count >= 3
    }

    func currentSession(at date: Date, zone: TimeZone) -> Session? {
        let day = LocalDay(at: date, zone: zone)
        return sessions.last { $0.sheetID == activeSheetID && !$0.finished && $0.day.key == day.key }
    }

    func last(_ movement: Movement, excluding sessionID: UUID?) -> Entry? {
        lastPerformance(movement, excluding: sessionID)?.entry
    }

    func lastPerformance(_ movement: Movement, excluding sessionID: UUID?) -> (session: Session, entry: Entry)? {
        sessions.reversed().lazy.filter { $0.id != sessionID }.compactMap { session in
            session.entry(for: movement).map { (session: session, entry: $0) }
        }.max {
            ($0.entry.sets.last?.recordedAt ?? .distantPast) < ($1.entry.sets.last?.recordedAt ?? .distantPast)
        }
    }

    static func week(at date: Date, zone: TimeZone) -> DateInterval? {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = zone
        return calendar.dateInterval(of: .weekOfYear, for: date)
    }

    func weeklyCount(at date: Date, zone: TimeZone) -> Int {
        guard let week = Self.week(at: date, zone: zone) else { return 0 }
        return sessions.lazy.filter {
            !$0.entries.isEmpty && $0.startedAt >= week.start && $0.startedAt < week.end
        }.count
    }

    mutating func roll(to date: Date, zone: TimeZone) {
        let day = LocalDay(at: date, zone: zone)
        for index in sessions.indices where sessions[index].day.key != day.key && !sessions[index].finished {
            sessions[index].finished = true
        }
        if let undo, !sessions.contains(where: { $0.id == undo.sessionID && !$0.finished }) {
            self.undo = nil
        }
        sessions.removeAll { $0.finished && $0.entries.isEmpty }
    }

    @discardableResult
    mutating func record(_ value: Int?, for movement: Movement, at date: Date, zone: TimeZone,
                         continuing sessionID: UUID? = nil) -> Bool {
        if let value, !(1...movement.unit.maximum).contains(value) { return false }
        let existing = sessionID.flatMap { id in
            sessions.first { $0.id == id && $0.sheetID == activeSheetID && !$0.finished }
        } ?? currentSession(at: date, zone: zone)
        guard existing != nil || value != nil else { return false }

        let sheet = activeSheet
        let before = existing ?? Session(sheetID: sheet.id, sheetName: sheet.name,
                                         startedAt: date, day: LocalDay(at: date, zone: zone))
        var session = before
        let index = session.entries.firstIndex { $0.matches(movement) }
        if let value {
            let set = TrainingSet(value: value, recordedAt: date)
            if let index {
                session.entries[index].sets.append(set)
            } else {
                session.entries.append(Entry(movement: movement, sets: [set]))
            }
        } else {
            guard let index, !session.entries[index].sets.isEmpty else { return false }
            session.entries[index].sets.removeLast()
            if session.entries[index].sets.isEmpty { session.entries.remove(at: index) }
        }

        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else {
            sessions.append(session)
        }
        undo = TrainingUndo(sessionID: session.id, snapshot: before, movementID: movement.id)
        updateWeek(at: session.startedAt, zone: TimeZone(identifier: session.day.zoneID) ?? zone,
                   earnedAt: date, sheetID: sheet.id)
        updateBest(for: movement, in: session)
        return true
    }

    mutating func undoRecord(at date: Date, zone: TimeZone) {
        guard let undo, let index = sessions.firstIndex(where: { $0.id == undo.sessionID }) else { return }
        let current = sessions[index]
        let changed = (current.entries + undo.snapshot.entries).first {
            current.entry(for: $0.movement) != undo.snapshot.entry(for: $0.movement)
        }
        if undo.snapshot.entries.isEmpty {
            sessions.remove(at: index)
        } else {
            sessions[index] = undo.snapshot
        }
        self.undo = nil
        let zone = TimeZone(identifier: undo.snapshot.day.zoneID) ?? zone
        updateWeek(at: undo.snapshot.startedAt, zone: zone, earnedAt: date, sheetID: undo.snapshot.sheetID)
        if let changed { updateBest(for: changed.movement, in: undo.snapshot) }
    }

    mutating func finish(at date: Date, zone: TimeZone) {
        guard let id = currentSession(at: date, zone: zone)?.id,
              let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].finished = true
        sessions.removeAll { $0.entries.isEmpty }
        undo = nil
    }

    static func masteryKey(_ movement: Movement, sheetID: String) -> String { "\(sheetID)/\(movement.id)" }

    mutating func toggleMastery(_ movement: Movement, at date: Date) {
        let key = Self.masteryKey(movement, sheetID: activeSheetID)
        let id = "mastery/\(key)"
        if mastery.remove(key) != nil {
            milestones.removeAll { $0.id == id && !$0.used }
        } else {
            mastery.insert(key)
            if !seenMilestones.contains(id) {
                seenMilestones.insert(id)
                milestones.append(Milestone(id: id, kind: .mastery, date: date,
                                            sheetID: activeSheetID, movement: movement))
            }
        }
    }

    mutating func changeGoal(_ goal: Int) {
        guard (1...7).contains(goal) else { return }
        self.goal = goal
    }

    mutating func changeRestSeconds(_ seconds: Int) {
        guard Self.restRange.contains(seconds) else { return }
        savedRestSeconds = seconds == Self.defaultRestSeconds ? nil : seconds
    }

    private mutating func updateBest(for movement: Movement, in session: Session) {
        let id = "best/\(session.id)/\(movement.id):\(movement.unit.rawValue)"
        let index = milestones.firstIndex { $0.id == id }
        if let index, milestones[index].used { return }

        let previousBest = sessions.lazy
            .filter { $0.sheetID == session.sheetID && $0.id != session.id }
            .compactMap { $0.entry(for: movement)?.bestSet?.value }.max()
        guard let previousBest, let best = session.entry(for: movement)?.bestSet, best.value > previousBest else {
            if let index { milestones.remove(at: index) }
            return
        }
        if let index {
            milestones[index].bestValue = best.value
            milestones[index].date = best.recordedAt
        } else {
            milestones.append(Milestone(id: id, kind: .best, date: best.recordedAt,
                                        sheetID: session.sheetID, movement: movement, bestValue: best.value))
        }
    }

    private mutating func updateWeek(at date: Date, zone: TimeZone, earnedAt: Date, sheetID: String) {
        guard let week = Self.week(at: date, zone: zone) else { return }
        let id = "week/\(LocalDay(at: week.start, zone: zone).key)"
        let count = weeklyCount(at: date, zone: zone)
        if let existing = milestones.first(where: { $0.id == id }) {
            if !existing.used && count < (existing.target ?? 3) {
                milestones.removeAll { $0.id == id }
                seenMilestones.remove(id)
            }
        } else if count >= goal && !seenMilestones.contains(id) {
            seenMilestones.insert(id)
            milestones.append(Milestone(id: id, kind: .week, date: earnedAt, sheetID: sheetID, target: goal))
        }
    }
}
