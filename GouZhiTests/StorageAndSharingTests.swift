import XCTest

final class StorageAndSharingTests: XCTestCase {
    private func project() -> Project {
        let row = Counter(name: "Round")
        let stitch = Counter(name: "Stitch", kind: .stitch, value: 2, min: 0, resetAt: 12, linkTo: row.id)
        return Project(name: "Bear", coverFilename: "private.jpg", parts: [Part(counters: [row, stitch], mainCounterID: stitch.id, patternPages: [PatternPage(filename: "private.pdf")], textPattern: PatternParse.lines("Rnd 1: sc (12)"), reminders: [RowReminder(atRow: 2, text: "Change yarn")], roundTargets: [1: 12], videoMarks: [1: 123])], yarns: [Yarn(brand: "Cotton", color: "01", batch: "A", amount: "40g")], hookSize: "2.5 mm", size: "M", photos: ["secret.jpg"], videoLink: "https://youtu.be/demo")
    }
    func testShareRoundTripAndNoImageReferences() throws {
        let p = project(); let encoded = try XCTUnwrap(ShareCode.encode(p)); let copy = try XCTUnwrap(ShareCode.decode(encoded.text))
        XCTAssertFalse(encoded.omittedText); XCTAssertEqual(copy.name, p.name); XCTAssertEqual(copy.yarns, p.yarns)
        XCTAssertEqual(copy.parts[0].roundTargets, [1: 12]); XCTAssertEqual(copy.parts[0].videoMarks, [1: 123])
        XCTAssertEqual(copy.parts[0].textPattern?.first?.target, 12); XCTAssertEqual(copy.parts[0].reminders.first?.text, "Change yarn")
        XCTAssertNotEqual(copy.id, p.id); XCTAssertNotEqual(copy.parts[0].id, p.parts[0].id)
        XCTAssertEqual(copy.parts[0].counters[1].linkTo, copy.parts[0].counters[0].id)
        XCTAssertTrue(copy.photos.isEmpty); XCTAssertNil(copy.coverFilename); XCTAssertTrue(copy.parts[0].patternPages.isEmpty)
    }
    func testTolerantShareTextAndCorruptInput() throws {
        let code = try XCTUnwrap(ShareCode.encode(project())).text
        let brokenLines = code.enumerated().map { $0.offset % 40 == 0 ? "\n" + String($0.element) : String($0.element) }.joined()
        XCTAssertNotNil(ShareCode.decode("A friend's note \n" + brokenLines.replacingOccurrences(of: "#", with: "＃") + "\nEnd"))
        XCTAssertNil(ShareCode.decode("#钩织计数#%%%%#")); XCTAssertNil(ShareCode.decode("#钩织计数#A#"))
    }
    func testLongTextFallsBackAndReportsOmission() throws {
        var p = project()
        p.parts[0].textPattern = (0..<2000).map { _ in PatternLine(text: UUID().uuidString + UUID().uuidString) }
        let encoded = try XCTUnwrap(ShareCode.encode(p))
        XCTAssertTrue(encoded.omittedText); XCTAssertLessThanOrEqual(encoded.text.count, ShareCode.maxTextLength)
        XCTAssertNil(ShareCode.decode(encoded.text)?.parts[0].textPattern)
    }
    func testZlibRejectsCorruptedChecksumAndHugeInput() throws {
        var packed = try XCTUnwrap(ShareCode.pack(Data("hello".utf8)))
        packed[packed.count - 1] ^= 1; XCTAssertNil(ShareCode.unpack(packed))
        XCTAssertNil(ShareCode.pack(Data(repeating: 1, count: ShareCode.maxJSONLength + 1)))
    }
    func testOldModelsDecodeMissingFields() throws {
        let p = try JSONDecoder().decode(Project.self, from: Data("{}".utf8))
        XCTAssertEqual(p.parts.count, 1); XCTAssertEqual(p.parts[0].row, 1); XCTAssertEqual(p.totalSeconds, 0)
        let data = try JSONDecoder().decode(AppData.self, from: Data("{}".utf8))
        XCTAssertTrue(data.projects.isEmpty); XCTAssertEqual(data.quick.selectedCounter?.value, 0); XCTAssertTrue(data.preferences.keepAwake)
        XCTAssertEqual(try JSONDecoder().decode(Tracker.self, from: Data("{}".utf8)).zoomScale, 1)
    }
    func testStoreAtomicUpdatesDoNotLoseOtherChanges() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let a = try Store(root: root), b = try Store(root: root)
        try a.update { $0.projects = [project()]; $0.recentID = $0.projects[0].id }
        let initial = try a.load(); let part = initial.currentPart
        try b.update { _ = $0.count(projectID: initial.recentID, partID: part.id, counterID: part.counters[1].id, delta: 1) }
        try a.update { $0.preferences.haptics = false }
        let loaded = try a.load()
        XCTAssertEqual(loaded.currentPart.counters[1].value, 3); XCTAssertFalse(loaded.preferences.haptics)
        XCTAssertEqual(loaded.undo[part.historyKey]?.count, 1)
        XCTAssertThrowsError(try a.file("../private"))
    }
    func testDecodeFailureNeverOverwritesOriginalFile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try Store(root: root); let bad = Data("not JSON".utf8)
        try bad.write(to: store.json)
        XCTAssertThrowsError(try store.update { $0.projects = [] })
        XCTAssertEqual(try Data(contentsOf: store.json), bad)
    }
    func testConcurrentCountersRemainAtomic() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try Store(root: root), second = try Store(root: root)
        let state = try store.update { _ in }, part = state.quick
        let counter = try XCTUnwrap(part.selectedCounter)
        let errorLock = NSLock(); var failures = 0
        DispatchQueue.concurrentPerform(iterations: 100) { i in
            do { try (i % 2 == 0 ? store : second).update { _ = $0.count(projectID: nil, partID: part.id, counterID: counter.id, delta: 1) } }
            catch { errorLock.lock(); failures += 1; errorLock.unlock() }
        }
        XCTAssertEqual(failures, 0)
        let result = try store.load()
        XCTAssertEqual(result.quick.selectedCounter?.value, 100); XCTAssertEqual(result.undo[part.historyKey]?.count, 50)
    }
    func testExportIsZipAndIncludesFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try Store(root: root); try store.update { $0.projects = [project()] }
        let filename = try store.writeFile(Data("image".utf8), extension: "jpg")
        let orphan = try store.writeFile(Data("deleted image".utf8), extension: "jpg")
        try store.update { $0.projects[0].coverFilename = filename }
        let zip = try store.exportAll(); defer { try? FileManager.default.removeItem(at: zip) }
        let bytes = try Data(contentsOf: zip)
        XCTAssertEqual(Array(bytes.prefix(2)), [0x50, 0x4b])
        XCTAssertNotNil(bytes.range(of: Data(filename.utf8))); XCTAssertNil(bytes.range(of: Data(orphan.utf8)))
    }
    func testTrialStartReceiptAndPaidLaunchRules() throws {
        let now = Date(), old = Date().addingTimeInterval(-90 * 86400)
        var e = Entitlement(firstOpen: old, proStartedAt: now)
        XCTAssertTrue(e.isPremium(at: now)); XCTAssertEqual(e.remainingDays(at: now), 30)
        e.trialClaimedAt = now
        XCTAssertTrue(e.isPremium(at: now))
        e.trialClaimedAt = old
        XCTAssertFalse(e.isPremium(at: now)); XCTAssertFalse(e.hasPro(at: now, arguments: ["-paid-mode"]))
        XCTAssertEqual(e.hasPro(at: now, arguments: []), Launch.freePeriod)
        e.purchasedPro = true; XCTAssertTrue(e.hasPro(at: now, arguments: ["-expired"]))
        let legacy = try JSONDecoder().decode(Entitlement.self, from: Data("{}".utf8)); XCTAssertNil(legacy.proStartedAt)
        let reinstall = Entitlement(firstOpen: now, proStartedAt: old)
        XCTAssertFalse(reinstall.isPremium(at: now))
    }
    func testMilestonesOnlyAnnouncedOnce() {
        var p = project(); p.status = .completed; p.totalSeconds = 360_000; p.parts[0].counters[0].value = 1001
        var seen = Set<String>()
        let fresh = Milestones.fresh(projects: [p], announced: &seen)
        XCTAssertTrue(fresh.contains("first")); XCTAssertTrue(fresh.contains("hours")); XCTAssertTrue(fresh.contains("rows-" + p.id.uuidString))
        XCTAssertTrue(fresh.contains("half-" + p.id.uuidString))
        XCTAssertTrue(Milestones.fresh(projects: [p], announced: &seen).isEmpty)
        let ten = (0..<10).map { _ -> Project in var copy = p; copy.id = UUID(); return copy }
        XCTAssertTrue(Milestones.fresh(projects: ten, announced: &seen).contains("ten"))
    }
    func testLaunchArgumentsControlSingleProDecision() {
        let expired = Entitlement(firstOpen: Date().addingTimeInterval(-60 * 86400))
        XCTAssertEqual(Launch.isFree(arguments: []), Launch.freePeriod)
        for flag in ["-paid-mode", "-paywall", "-expired"] {
            XCTAssertFalse(Launch.isFree(arguments: [flag])); XCTAssertFalse(expired.hasPro(at: Date(), arguments: [flag]))
        }
        XCTAssertEqual(expired.hasPro(at: Date(), arguments: []), Launch.freePeriod)
    }
}
