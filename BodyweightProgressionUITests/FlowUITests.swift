import XCTest

final class FlowUITests: XCTestCase {
    private let push = "today.builtin.push.0"
    private let hang = "today.builtin.pull.0"

    override func setUpWithError() throws {
        continueAfterFailure = false
        executionTimeAllowance = 900
    }

    func testFreshLaunchLogUndoFinishAndHistoryExport() {
        let app = launch()
        for id in [push, hang, "today.builtin.squat.0", "today.builtin.hold.0"] {
            XCTAssertTrue(element(id, in: app).waitForExistence(timeout: 8))
        }
        tap(push, in: app)
        tap("number.quick.5", in: app)
        XCTAssertTrue(element(push, in: app).label.contains("5"))
        tap("entry.undo", in: app)
        XCTAssertFalse(element("session.finish", in: app).exists)
        tap(push, in: app)
        tap("number.quick.8", in: app)
        tap("session.finish", in: app)
        XCTAssertTrue(element("last.builtin.push.0", in: app).label.contains("8"))
        tap("tab.history", in: app)
        tap("history.session", in: app)
        XCTAssertTrue(element("history.sets.builtin.push.0", in: app).label.contains("8"))
        tap("history.done", in: app)
        tap("history.export", in: app)
        XCTAssertTrue(element("share.requested", in: app).waitForExistence(timeout: 8))
        app.terminate()
        let relaunched = launch(reset: false)
        XCTAssertTrue(element("last.builtin.push.0", in: relaunched).label.contains("8"))
    }

    func testGuidedWorkoutLogsTwoSetsSkipsRestAndAdvances() {
        let app = launch(flags: ["-demo"])
        tap("guide.start", in: app)
        XCTAssertTrue(element("guide.position", in: app).label.contains("1 of 4"))
        XCTAssertTrue(element("guide.last", in: app).label.contains("1 set: 8"))
        tap("guide.record", in: app)
        tap("number.quick.8", in: app)
        XCTAssertTrue(element("rest.countdown", in: app).waitForExistence(timeout: 5))
        tap("guide.record", in: app)
        tap("number.quick.8", in: app)
        XCTAssertTrue(element("guide.sets", in: app).label.contains("2 sets: 8, 8"))
        XCTAssertTrue(element("rest.countdown", in: app).waitForExistence(timeout: 5))
        tap("rest.skip", in: app)
        XCTAssertFalse(element("rest.countdown", in: app).exists)
        tap("guide.next", in: app)
        XCTAssertTrue(element("guide.position", in: app).label.contains("2 of 4"))
        XCTAssertTrue(element("guide.last", in: app).label.contains("1 set: 20"))
        tap("guide.exit", in: app)
        XCTAssertTrue(element(push, in: app).label.contains("2 sets: 8, 8"))
        tap("session.finish", in: app)
        XCTAssertTrue(element("last.builtin.push.0", in: app).label.contains("2 sets: 8, 8"))
        tap("tab.history", in: app)
        tap("history.session", in: app)
        XCTAssertTrue(element("history.sets.builtin.push.0", in: app).label.contains("2 sets: 8, 8"))
    }

    func testProgressionRowOpensMovementDemonstration() {
        let app = launch()
        tap("progress.builtin.push", in: app)
        let movement = "builtin.push.0"
        let card = element("demo.card.\(movement)", in: app)
        XCTAssertFalse(card.exists)
        tap("demo.toggle.\(movement)", in: app)
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        for id in ["demo.pose.start.\(movement)", "demo.pose.end.\(movement)",
                   "demo.tip.\(movement).1", "demo.tip.\(movement).2", "demo.tip.\(movement).3"] {
            XCTAssertTrue(element(id, in: app).exists, id)
        }
        tap("demo.toggle.\(movement)", in: app)
        XCTAssertFalse(card.exists)
    }

    func testCustomNumberProgressionAndSharing() {
        let app = launch()
        tap(hang, in: app)
        let field = element("number.field", in: app)
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4) + "325")
        tap("number.keyboard.done", in: app)
        tap("number.save", in: app)
        XCTAssertTrue(element(hang, in: app).label.contains("325"))
        tap("progress.builtin.push", in: app)
        tap("master.builtin.push.2", in: app)
        tap("use.builtin.push.2", in: app)
        tap("progress.done", in: app)
        XCTAssertTrue(element("today.builtin.push.2", in: app).exists)
        tap("home.milestone", in: app)
        tap("card.copy", in: app)
        XCTAssertTrue(element("card.copy.status", in: app).exists)
        tap("card.share", in: app)
        XCTAssertTrue(element("share.requested", in: app).waitForExistence(timeout: 8))
    }

    func testExpiredTrialCanImportAndRestorePreviousSheet() {
        let app = launch(flags: ["-expired"], importCode: fixture())
        tap(push, in: app)
        tap("number.quick.8", in: app)
        tap("home.import", in: app)
        XCTAssertFalse(element("import.preview.name", in: app).exists)
        tap("import.paste", in: app)
        XCTAssertEqual(element("import.preview.name", in: app).label, "Park Sheet")
        tap("import.confirm", in: app)
        XCTAssertTrue(element("home.sheet", in: app).waitForExistence(timeout: 5))
        XCTAssertEqual(element("home.sheet", in: app).label, "Park Sheet")
        tap("tab.settings", in: app)
        tap("settings.sheet.starter", in: app)
        tap("settings.new", in: app)
        XCTAssertTrue(element("paywall.buy", in: app).waitForExistence(timeout: 5))
        tap("paywall.close", in: app)
        tap("tab.history", in: app)
        tap("history.export", in: app)
        XCTAssertTrue(element("share.requested", in: app).waitForExistence(timeout: 8))
    }

    func testThirdDistinctDayRequestsReviewWithoutMilestoneSharing() {
        let app = launch()
        for day in 0..<3 {
            if day > 0 {
                tap("tab.settings", in: app)
                tap("testing.advance", in: app)
                tap("tab.today", in: app)
            }
            tap(push, in: app)
            tap(day == 0 ? "number.quick.8" : "number.quick.9", in: app)
            if day < 2 { XCTAssertFalse(element("review.requested", in: app).exists) }
        }
        XCTAssertTrue(element("review.requested", in: app).waitForExistence(timeout: 8))
    }

    func testInvalidImportShowsErrorAndDoesNotReplaceSheet() {
        let app = launch(importCode: "BW2:invalid")
        tap("home.import", in: app)
        tap("import.paste", in: app)
        XCTAssertTrue(element("import.status", in: app).exists)
        XCTAssertFalse(element("import.confirm", in: app).exists)
        tap("import.close", in: app)
        XCTAssertTrue(element(push, in: app).exists)
    }

    func testStoreScreenshots() {
        for language in ["en", "zh-Hans", "zh-Hant"] {
            let app = launch(language: language, flags: ["-demo"])
            shot("store-\(language)-01-today", app)
            tap(hang, in: app)
            shot("store-\(language)-02-entry", app)
            tap("number.close", in: app)
            tap("progress.builtin.push", in: app)
            shot("store-\(language)-03-progression", app)
            tap("progress.done", in: app)
            tap("tab.history", in: app)
            shot("store-\(language)-04-history", app)
            tap("history.card", in: app)
            XCTAssertTrue(element("card.headline", in: app).waitForExistence(timeout: 5))
            XCTAssertTrue(element("card.qr", in: app).waitForExistence(timeout: 5))
            shot("store-\(language)-05-share", app)
            app.terminate()
        }
        let app = launch(language: "zh-Hans", flags: ["-paywall"])
        XCTAssertTrue(element("paywall.buy", in: app).waitForExistence(timeout: 5))
        shot("paid-01-paywall", app)
    }

    private func launch(language: String = "en", flags: [String] = [], reset: Bool = true,
                        importCode: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(\(language))", "-AppleLocale", language]
            + (reset ? ["-reset"] : []) + flags
        if let importCode { app.launchEnvironment["BW_IMPORT_CODE"] = importCode }
        app.launch()
        let first = flags.contains("-paywall") ? "paywall.buy" : "tab.today"
        XCTAssertTrue(element(first, in: app).waitForExistence(timeout: 15))
        return app
    }

    private func tap(_ id: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let target = element(id, in: app)
        _ = target.waitForExistence(timeout: 3)
        for _ in 0..<5 where !target.isHittable { app.swipeUp() }
        XCTAssertTrue(target.isHittable, "Cannot tap \(id)", file: file, line: line)
        if target.isHittable { target.tap() }
    }

    private func element(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func shot(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func fixture() -> String {
        let template = #"{"n":"Park Sheet","g":[{"n":"Push","m":[{"n":"Bench push-up","u":"reps"}]}]}"#
        return "BW1:" + Data(template.utf8).base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
    }
}
