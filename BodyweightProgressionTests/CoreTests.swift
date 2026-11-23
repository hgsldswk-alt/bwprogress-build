import CoreImage
import XCTest

final class CoreTests: XCTestCase {
    private let zone = TimeZone(secondsFromGMT: 0)!
    private let monday = Date(timeIntervalSince1970: 1_795_392_000)

    func testStarterAndLastScoreAreMovementAndUnitSpecific() throws {
        var state = TrainingState()
        let group = try XCTUnwrap(state.activeSheet.groups.first)
        let first = try XCTUnwrap(group.current)
        let harder = group.moves[1]
        XCTAssertEqual(state.activeSheet.currentMoves.count, 4)
        XCTAssertEqual(state.activeSheet.groups.map { $0.moves.count }, [4, 4, 4, 4])
        state.record(8, for: first, at: monday, zone: zone)
        let initial = try XCTUnwrap(state.currentSession(at: monday, zone: zone))
        XCTAssertNil(state.last(first, excluding: initial.id))
        state.record(8, for: first, at: monday.addingTimeInterval(1), zone: zone)
        state.record(6, for: first, at: monday.addingTimeInterval(2), zone: zone)
        state.finish(at: monday, zone: zone)
        state.record(12, for: first, at: monday.addingTimeInterval(60), zone: zone)
        let next = try XCTUnwrap(state.currentSession(at: monday, zone: zone))
        XCTAssertEqual(state.last(first, excluding: next.id)?.sets.map(\.value), [8, 8, 6])
        XCTAssertNil(state.last(harder, excluding: next.id))
        var differentUnit = first
        differentUnit.unit = .seconds
        XCTAssertNil(state.last(differentUnit, excluding: next.id))
        XCTAssertEqual(state.history.count, 2)
    }

    func testMultipleSetsRoundTripAndUndoOnlyLatestChange() throws {
        var state = TrainingState()
        let first = try XCTUnwrap(state.activeSheet.currentMoves.first)
        state.record(5, for: first, at: monday, zone: zone)
        state.record(5, for: first, at: monday.addingTimeInterval(1), zone: zone)
        state.record(10, for: first, at: monday.addingTimeInterval(2), zone: zone)
        XCTAssertEqual(state.history.first?.entries.first?.sets.map(\.value), [5, 5, 10])
        XCTAssertEqual(state.weeklyCount(at: monday, zone: zone), 1)
        state = try JSONDecoder().decode(TrainingState.self, from: JSONEncoder().encode(state))
        state.undoRecord(at: monday, zone: zone)
        XCTAssertEqual(state.history.first?.entries.first?.sets.map(\.value), [5, 5])
        state.record(nil, for: first, at: monday, zone: zone)
        XCTAssertEqual(state.history.first?.entries.first?.sets.map(\.value), [5])
        state.record(nil, for: first, at: monday, zone: zone)
        XCTAssertTrue(state.history.isEmpty)
        XCTAssertEqual(state.weeklyCount(at: monday, zone: zone), 0)
        state.undoRecord(at: monday, zone: zone)
        XCTAssertEqual(state.history.first?.entries.first?.sets.map(\.value), [5])
        XCTAssertFalse(state.record(9999, for: first, at: monday, zone: zone))
        XCTAssertEqual(state.history.first?.entries.first?.sets.map(\.value), [5])
        XCTAssertEqual(try JSONDecoder().decode(TrainingState.self, from: JSONEncoder().encode(state)), state)
    }

    func testV1SingleValueDecodesAsOneSetAndCanBeExtended() throws {
        let fixture = #"""
        {
          "sheets": [], "activeSheetID": "starter", "mastery": [], "milestones": [], "seenMilestones": [], "goal": 3,
          "sessions": [{
            "id": "199D358C-F441-4076-B1F5-78D4FCF0129E", "sheetID": "starter", "sheetName": "sheet.starter",
            "startedAt": 0, "day": {"key": "2001-01-01", "zoneID": "GMT"}, "finished": false,
            "entries": [{
              "movement": {"id": "builtin.push.0", "name": "move.push.0", "unit": "reps", "hint": "move.push.0.hint"},
              "value": 8, "recordedAt": 10
            }]
          }]
        }
        """#
        var state = try JSONDecoder().decode(TrainingState.self, from: Data(fixture.utf8))
        let original = try XCTUnwrap(state.history.first)
        let move = try XCTUnwrap(original.entries.first?.movement)
        XCTAssertEqual(original.entries.first?.sets, [TrainingSet(value: 8, recordedAt: Date(timeIntervalSinceReferenceDate: 10))])
        XCTAssertEqual(state.restSeconds, 90)
        state.record(6, for: move, at: Date(timeIntervalSinceReferenceDate: 20), zone: zone)
        XCTAssertEqual(state.history.first?.id, original.id)
        XCTAssertEqual(state.history.first?.entries.first?.sets.map(\.value), [8, 6])
        XCTAssertEqual(try JSONDecoder().decode(TrainingState.self, from: JSONEncoder().encode(state)), state)
    }

    func testPersonalBestUsesHighestSetAcrossSessions() throws {
        var state = TrainingState()
        let move = try XCTUnwrap(state.activeSheet.currentMoves.first)
        state.record(10, for: move, at: monday, zone: zone)
        state.record(4, for: move, at: monday.addingTimeInterval(1), zone: zone)
        state.finish(at: monday.addingTimeInterval(2), zone: zone)
        let later = monday.addingTimeInterval(60)
        state.record(8, for: move, at: later, zone: zone)
        state.record(10, for: move, at: later.addingTimeInterval(1), zone: zone)
        XCTAssertTrue(state.milestones.filter { $0.kind == .best }.isEmpty)
        state.record(12, for: move, at: later.addingTimeInterval(2), zone: zone)
        XCTAssertEqual(state.milestones.filter { $0.kind == .best }.map(\.bestValue), [12])
        state.record(6, for: move, at: later.addingTimeInterval(3), zone: zone)
        XCTAssertEqual(state.milestones.filter { $0.kind == .best }.map(\.bestValue), [12])
        state.record(nil, for: move, at: later.addingTimeInterval(4), zone: zone)
        state.record(nil, for: move, at: later.addingTimeInterval(5), zone: zone)
        XCTAssertTrue(state.milestones.filter { $0.kind == .best }.isEmpty)
        state.undoRecord(at: later.addingTimeInterval(6), zone: zone)
        XCTAssertEqual(state.milestones.filter { $0.kind == .best }.map(\.bestValue), [12])
    }

    func testRestDurationDefaultsAndBoundsPersist() throws {
        var state = TrainingState()
        XCTAssertEqual(state.restSeconds, 90)
        state.changeRestSeconds(30)
        state.changeRestSeconds(29)
        XCTAssertEqual(state.restSeconds, 30)
        state.changeRestSeconds(300)
        state.changeRestSeconds(301)
        XCTAssertEqual(state.restSeconds, 300)
        let restored = try JSONDecoder().decode(TrainingState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(restored.restSeconds, 300)
    }

    func testGuidedOrderUsesCurrentVariantsAndSheetOrder() throws {
        var sheet = TrainingSheet.starter()
        let day = LocalDay(at: monday, zone: zone)
        XCTAssertEqual(sheet.currentMoves.map(\.id),
                       ["builtin.push.0", "builtin.pull.0", "builtin.squat.0", "builtin.hold.0"])
        let selected = sheet.groups[0].moves[2].id
        sheet.groups[0].currentID = selected
        sheet.groups.swapAt(0, 2)
        var workout = try XCTUnwrap(GuidedWorkout(sheet: sheet, day: day))
        for (index, id) in ["builtin.squat.0", "builtin.pull.0", selected, "builtin.hold.0"].enumerated() {
            XCTAssertEqual(workout.index, index)
            XCTAssertEqual(workout.movement?.id, id)
            XCTAssertEqual(workout.hasNext, index < 3)
            workout.advance()
        }
        workout.advance()
        XCTAssertEqual(workout.index, 4)
        XCTAssertNil(workout.movement)
        sheet.groups = []
        XCTAssertNil(GuidedWorkout(sheet: sheet, day: day))
    }

    func testOvernightContinuationPreservesOriginalDayAndZone() throws {
        let start = monday.addingTimeInterval(86_395)
        let midnight = start.addingTimeInterval(10)
        var state = TrainingState()
        let moves = state.activeSheet.currentMoves
        state.record(5, for: moves[0], at: start, zone: zone)
        let prior = try XCTUnwrap(state.history.first)
        let east = TimeZone(secondsFromGMT: 9 * 3600)!
        state.record(30, for: moves[1], at: midnight, zone: east, continuing: prior.id)
        state.roll(to: midnight, zone: east)
        XCTAssertEqual(state.history.first?.day, prior.day)
        XCTAssertEqual(state.history.first?.entries.count, 2)
        XCTAssertNil(state.currentSession(at: midnight, zone: east))
        state.record(12, for: moves[0], at: midnight, zone: east)
        XCTAssertEqual(state.history.count, 2)
        XCTAssertNotEqual(state.history.first?.day, prior.day)
    }

    func testWeeklyMasteryAndReviewRules() throws {
        var state = TrainingState()
        let move = try XCTUnwrap(state.activeSheet.currentMoves.first)
        for offset in 0..<3 {
            let date = monday.addingTimeInterval(Double(offset) * 86_400)
            state.record(8, for: move, at: date, zone: zone)
        }
        let newest = monday.addingTimeInterval(2 * 86_400)
        XCTAssertEqual(state.weeklyCount(at: newest, zone: zone), 3)
        XCTAssertTrue(state.reviewEligible)
        XCTAssertEqual(state.milestones.filter { $0.kind == .week }.count, 1)
        state.undoRecord(at: newest, zone: zone)
        XCTAssertFalse(state.reviewEligible)
        XCTAssertTrue(state.milestones.isEmpty)
        state.toggleMastery(move, at: newest)
        XCTAssertEqual(state.milestones.count, 1)
        state.toggleMastery(move, at: newest)
        XCTAssertTrue(state.milestones.isEmpty)
        state.toggleMastery(move, at: newest)
        XCTAssertTrue(state.milestones.isEmpty)
        XCTAssertEqual(state.history.count, 2)
        let nextWeek = monday.addingTimeInterval(7 * 86_400)
        XCTAssertEqual(state.weeklyCount(at: nextWeek, zone: zone), 0)
    }

    func testTransferRoundTripAndRejectsInvalidInput() throws {
        let source = TrainingSheet.starter()
        let code = try SheetCode.encode(source)
        XCTAssertLessThanOrEqual(code.count, 4096)
        let decoded = try SheetCode.decode(" \(code)\n")
        XCTAssertTrue(SheetCode.matches(source, decoded))
        XCTAssertNotEqual(source.id, decoded.id)
        XCTAssertThrowsError(try SheetCode.decode("BW2:" + String(code.dropFirst(4))))
        XCTAssertThrowsError(try SheetCode.decode(String(repeating: "x", count: 4097)))
        XCTAssertThrowsError(try SheetCode.decode("BW1:<>"))
        let badUnit = #"{"n":"Bad","g":[{"n":"A","m":[{"n":"B","u":"kg"}]}]}"#
        let token = Data(badUnit.utf8).base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
        XCTAssertThrowsError(try SheetCode.decode("BW1:" + token))
        var invalid = source
        invalid.groups = Array(repeating: source.groups[0], count: 9)
        XCTAssertThrowsError(try SheetCode.encode(invalid))
    }

    func testCSVAndEscapingWhileTrialExpired() throws {
        var state = TrainingState()
        var move = try XCTUnwrap(state.activeSheet.currentMoves.first)
        move.id = "custom"
        move.name = "  =SUM(\"A\", 2)"
        state.record(7, for: move, at: monday, zone: zone)
        state.record(6, for: move, at: monday.addingTimeInterval(1), zone: zone)
        let rights = Entitlement(firstOpen: monday.addingTimeInterval(-40 * 86_400))
        XCTAssertFalse(rights.hasPro(at: monday))
        let bytes = TrainingCSV.render(state.history)
        XCTAssertTrue(bytes.contains("\"'  =SUM(\"\"A\"\", 2)\""))
        XCTAssertTrue(bytes.contains(",\"7\",\"1\"\r\n"))
        XCTAssertTrue(bytes.hasSuffix(",\"6\",\"2\"\r\n"))
        XCTAssertFalse(bytes.contains("custom"))
        XCTAssertEqual(TrainingCSV.escaped("@x"), "\"'@x\"")
    }

    func testTrialRestorePurchaseAndExpiryBoundaries() throws {
        var rights = Entitlement(firstOpen: monday)
        XCTAssertFalse(Launch.freePeriod)
        XCTAssertTrue(rights.hasPro(at: monday))
        XCTAssertTrue(rights.hasPro(at: rights.trialEnd.addingTimeInterval(-1)))
        XCTAssertFalse(rights.hasPro(at: rights.trialEnd))
        rights.verifyTrial(originalDate: monday.addingTimeInterval(86_400))
        XCTAssertEqual(rights.trialStart, monday)
        var reinstalled = Entitlement(firstOpen: monday.addingTimeInterval(50 * 86_400))
        reinstalled.verifyTrial(originalDate: monday)
        XCTAssertEqual(reinstalled.trialStart, monday)
        XCTAssertFalse(reinstalled.hasPro(at: reinstalled.firstOpen))
        reinstalled.purchasedPro = true
        XCTAssertTrue(reinstalled.hasPro(at: reinstalled.firstOpen))
        reinstalled.purchasedPro = false
        XCTAssertFalse(reinstalled.hasPro(at: reinstalled.firstOpen))
        rights.trialRevoked = true
        XCTAssertFalse(rights.hasPro(at: monday))
        rights.purchasedPro = true
        XCTAssertTrue(rights.hasPro(at: monday))
    }

    func testWidgetLosesPinnedRowAtExpiryAndRestartsWeek() throws {
        let state = TrainingState()
        let rights = Entitlement(firstOpen: monday)
        let snapshot = WidgetSnapshot(state: state, entitlement: rights, now: monday, zone: zone)
        XCTAssertNotNil(snapshot.movement(at: monday))
        XCTAssertNil(snapshot.movement(at: rights.trialEnd))
        XCTAssertEqual(snapshot.count(at: try XCTUnwrap(snapshot.weekEnd)), 0)
    }

    func testDownloadQRDecodesPreviewAndAppURL() throws {
        for appID in [nil, "1234567890"] as [String?] {
            let url = DownloadQR.url(appID: appID)
            let image = try XCTUnwrap(DownloadQR.image(for: url))
            let detector = try XCTUnwrap(CIDetector(ofType: CIDetectorTypeQRCode, context: nil,
                                                   options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]))
            let result = detector.features(in: image).compactMap { ($0 as? CIQRCodeFeature)?.messageString }
            XCTAssertEqual(result, [url.absoluteString])
        }
    }
}
