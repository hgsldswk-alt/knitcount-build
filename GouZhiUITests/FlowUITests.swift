import CoreGraphics
import XCTest

final class FlowUITests: XCTestCase {
    private enum ShotLanguage: String {
        case simplified = "zh-Hans", traditional = "zh-Hant", english = "en"

        var locale: String {
            switch self { case .simplified: return "zh_CN"; case .traditional: return "zh_TW"; case .english: return "en_US" }
        }
        var cardigan: String {
            switch self { case .simplified: return "燕麦色开衫"; case .traditional: return "燕麥色開襟衫"; case .english: return "Oatmeal cardigan" }
        }
        var projectsTitle: String { self == .english ? "My projects" : "我的作品" }
        var symbolsTitle: String {
            switch self { case .simplified: return "针法符号速查"; case .traditional: return "針法符號速查"; case .english: return "Stitch symbol guide" }
        }
    }

    private var app: XCUIApplication!
    private var countButton: XCUIElement { app.buttons["countButton"] }
    private var rowButton: XCUIElement { app.buttons["selectCounter-row"].firstMatch }
    private var currentLine: XCUIElement { app.staticTexts["currentPatternLine"].firstMatch }
    private var sharePreview: XCUIElement { app.images["sharePreview"].firstMatch }

    override func setUp() { continueAfterFailure = false; app = XCUIApplication() }
    private func launch(_ args: [String], language: ShotLanguage = .simplified) {
        app.launchArguments = ["-ui-testing", "-reset", "-AppleLanguages", "(\(language.rawValue))", "-AppleLocale", language.locale] + args
        app.launch()
    }
    private func tap(_ id: String, file: StaticString = #filePath, line: UInt = #line) {
        tap(app.buttons[id].firstMatch, id, file: file, line: line)
    }
    private func tap(_ element: XCUIElement, _ id: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(wait { element.exists && element.isEnabled && element.isHittable }, id, file: file, line: line)
        element.tap()
    }
    private func wait(_ predicate: @escaping () -> Bool) -> Bool {
        let e = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in predicate() }, object: nil)
        return XCTWaiter.wait(for: [e], timeout: 8) == .completed
    }
    private func hasValue(_ element: XCUIElement, _ value: Int) -> Bool {
        element.exists && (element.value as? String) == String(value)
    }
    private func describeValue(_ element: XCUIElement) -> String {
        guard element.exists else { return "exists=false" }
        let value = element.value.map { "\(String(reflecting: $0)) (\(type(of: $0)))" } ?? "nil"
        return "exists=true, value=\(value), label=\(element.label.debugDescription), hittable=\(element.isHittable)"
    }
    private func assertCount(_ value: Int, row: Int? = nil, file: StaticString = #filePath, line: UInt = #line) {
        let matches = wait { self.hasValue(self.countButton, value) && (row.map { self.hasValue(self.rowButton, $0) } ?? true) }
        guard !matches else { return }
        let expectedRow = row.map { String($0).debugDescription } ?? "(not checked)"
        XCTFail("Expected countButton.value=\(String(value).debugDescription), rowButton.value=\(expectedRow). " +
                "Actual countButton: \(describeValue(countButton)). Actual rowButton: \(describeValue(rowButton)).",
                file: file, line: line)
    }
    private func assertSymbols(_ language: ShotLanguage = .simplified, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(app.navigationBars[language.symbolsTitle].waitForExistence(timeout: 8), file: file, line: line)
    }
    private func assertChart(_ mode: String, file: StaticString = #filePath, line: UInt = #line) {
        let tracker = app.descendants(matching: .any).matching(identifier: "trackerMode").firstMatch
        XCTAssertTrue(wait { tracker.exists && tracker.label.contains(mode) && self.app.images["patternChart"].firstMatch.exists },
                      "trackerMode=\(mode), patternChart", file: file, line: line)
    }
    private func shot(_ name: String) throws {
        let png = XCUIScreen.main.screenshot().pngRepresentation
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        let env = ProcessInfo.processInfo.environment
        if let dir = env["SHOTS_DIR"] ?? env["TEST_RUNNER_SHOTS_DIR"], !dir.isEmpty {
            do {
                let folder = URL(fileURLWithPath: dir, isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try png.write(to: folder.appendingPathComponent(name + ".png"))
            } catch {
                let note = XCTAttachment(string: "Use xcresult attachment: \(error)"); note.lifetime = .keepAlways; add(note)
            }
        }
    }
    func testEmptyThreeCountsAndUndo() throws {
        launch(["-empty"])
        assertCount(0); try shot("01-empty-direct-counter")
        for count in 1...3 { tap("countButton"); assertCount(count); try shot("02-count-" + String(count)) }
        tap("undoButton"); assertCount(2); try shot("03-undo-two")
    }
    func testLinkedRoundSwitchProjectAndSymbols() throws {
        launch(["-demo", "-knit"])
        assertCount(14, row: 23)
        XCTAssertTrue(wait { self.currentLine.exists && self.currentLine.label.contains("第23圈") }); try shot("04-knit-home")
        for count in 15...23 { tap("countButton"); assertCount(count) }
        tap("countButton"); assertCount(0, row: 24)
        XCTAssertTrue(wait { self.currentLine.exists && self.currentLine.label.contains("第24圈") }); try shot("05-carry-next-round")
        tap("openProjects"); XCTAssertTrue(app.buttons["newProject"].waitForExistence(timeout: 5)); try shot("06-project-list")
        tap("projectName-燕麦色开衫"); assertCount(46, row: 46); try shot("07-text-size-highlight")
        tap("openProjects")
        tap("projectName-奶油色小熊玩偶"); assertCount(0, row: 24); try shot("08-return-preserved")
        tap("patternSymbols"); assertSymbols(); try shot("09-symbols")
    }
    func testTextImportAndAutomaticCompletionCard() throws {
        let text = "测试围巾\n第1行：锁针（12）\n第2行：短针（12）"
        app.launchEnvironment["GOUZHI_UI_PATTERN_TEXT"] = text
        launch(["-empty"])
        tap("addFromText")
        let editor = app.textViews["patternText"]
        XCTAssertTrue(wait { editor.exists && (editor.value as? String) == text },
                      "Expected full import text \(text.debugDescription). Actual patternText: \(describeValue(editor)).")
        let create = app.buttons["createTextProject"]
        if !create.isHittable {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: 0.78))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: 0.40))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertTrue(wait { create.exists && create.isEnabled && create.isHittable }); try shot("10-import-text")
        tap("createTextProject"); assertCount(0, row: 1)
        XCTAssertTrue(wait { self.currentLine.exists && self.currentLine.label.contains("第1行") }); try shot("11-import-direct-knit")
        tap("finishDirect")
        XCTAssertTrue(sharePreview.waitForExistence(timeout: 10)); try shot("12-completion-share-card")
        XCTAssertTrue(app.buttons["shareImage"].exists); XCTAssertTrue(app.buttons["copyCaption"].exists)
    }
    func testRingAndShareStoreScreenshots() throws {
        launch(["-demo", "-ring"]); assertCount(14, row: 8); assertChart("圆环"); try shot("13-ring-tracker")
        app.terminate(); launch(["-demo", "-grid"]); assertCount(14, row: 23); assertChart("网格"); try shot("13b-grid-tracker")
        app.terminate(); launch(["-demo", "-share"]); XCTAssertTrue(sharePreview.waitForExistence(timeout: 10)); try shot("14-share-card")
        tap("shareImage")
        let activityList = app.descendants(matching: .any).matching(identifier: "ActivityListView").firstMatch
        let copyActions = ["拷贝", "Copy", "复制"].map { app.buttons[$0].firstMatch }
        XCTAssertTrue(wait { activityList.exists || copyActions.contains { $0.exists } }); try shot("15-system-share")
    }
    func testLockAndUndoAfterManualEdit() throws {
        launch(["-empty"]); assertCount(0); tap("countButton"); assertCount(1)
        countButton.press(forDuration: 0.6)
        tap("resetCounter"); assertCount(0)
        tap("globalUndo"); assertCount(1)
        tap(app.descendants(matching: .any).matching(identifier: "knitMenu").firstMatch, "knitMenu")
        let lock = app.descendants(matching: .any).matching(identifier: "lockCounter").firstMatch
        let lockLabel = app.buttons["锁定计数"].firstMatch
        XCTAssertTrue(wait { lock.exists || lockLabel.exists }, "lockCounter")
        tap(lock.exists ? lock : lockLabel, "lockCounter")
        let zone = app.descendants(matching: .any).matching(identifier: "unlockZone").firstMatch
        XCTAssertTrue(wait { zone.exists && zone.isHittable && self.countButton.exists && !self.countButton.isEnabled })
        zone.press(forDuration: 0.6)
        tap("countButton"); assertCount(2); try shot("16-unlocked")
    }

    func testPaidModeShowsTrialAndExpiry() throws {
        let days = app.staticTexts["trialDaysRemaining"]
        let close = app.buttons["closeSheet"].firstMatch
        launch(["-paywall"])
        XCTAssertTrue(wait { days.exists && days.label == "完整体验还剩 30 天" && close.exists && close.isHittable })
        try shot("paid-01-paywall")
        tap("closeSheet"); assertCount(0)

        app.terminate(); launch(["-expired"])
        XCTAssertTrue(wait { days.exists && days.label == "完整体验还剩 0 天" })
        tap("closeSheet"); assertCount(0); tap("countButton"); assertCount(1)
    }

    func testStoreScreenshotsSimplifiedChinese() throws { try storeShots(.simplified, ring: "圆环", grid: "网格") }
    func testStoreScreenshotsTraditionalChinese() throws { try storeShots(.traditional, ring: "圓環", grid: "網格") }
    func testStoreScreenshotsEnglish() throws { try storeShots(.english, ring: "Ring", grid: "Grid") }

    private func storeShots(_ language: ShotLanguage, ring: String, grid: String) throws {
        let prefix = "store-\(language.rawValue)-"
        launch(["-demo", "-knit"], language: language)
        assertCount(14, row: 23)
        XCTAssertTrue(currentLine.waitForExistence(timeout: 8)); try shot(prefix + "01-knit")
        tap("openProjects")
        XCTAssertTrue(app.navigationBars[language.projectsTitle].waitForExistence(timeout: 8)); try shot(prefix + "02-projects")
        tap("projectName-" + language.cardigan); assertCount(46, row: 46)
        let medium = app.segmentedControls["sizePicker"].buttons["M"].firstMatch
        XCTAssertTrue(wait { medium.exists && medium.isSelected && self.currentLine.exists }); try shot(prefix + "03-sizes")
        tap("patternSymbols"); assertSymbols(language); try shot(prefix + "04-symbols")

        app.terminate(); launch(["-demo", "-ring"], language: language)
        assertCount(14, row: 8); assertChart(ring); try shot(prefix + "05-ring")
        app.terminate(); launch(["-demo", "-grid"], language: language)
        assertCount(14, row: 23); assertChart(grid); try shot(prefix + "06-grid")
        app.terminate(); launch(["-demo", "-share"], language: language)
        XCTAssertTrue(sharePreview.waitForExistence(timeout: 10)); try shot(prefix + "07-share")
    }
}
