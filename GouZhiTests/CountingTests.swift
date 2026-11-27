import Foundation
import XCTest
import CoreGraphics

final class CountingTests: XCTestCase {
    private func linked(rowValue: Int = 1, stitchValue: Int = 0) -> Part {
        let row = Counter(name: "Row", value: rowValue)
        let stitch = Counter(name: "Stitch", kind: .stitch, value: stitchValue, min: 0, resetAt: 6, linkTo: row.id)
        return Part(counters: [row, stitch], mainCounterID: stitch.id)
    }
    func testCoreReviewRequiresThreeActionsOnTwoLocalDates() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        let firstDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 23)))
        let nextDay = firstDay.addingTimeInterval(2 * 3600)
        let empty = try JSONDecoder().decode(CoreReviewProgress.self, from: Data("{}".utf8))
        XCTAssertFalse(empty.isEligible)
        var progress = CoreReviewProgress.recording(empty, at: firstDay, calendar: calendar)
        var twoDays = progress
        twoDays.record(at: nextDay, calendar: calendar)
        XCTAssertFalse(twoDays.isEligible)
        progress.record(at: firstDay, calendar: calendar)
        XCTAssertFalse(progress.isEligible)

        var sameDay = progress
        sameDay.record(at: firstDay, calendar: calendar)
        XCTAssertFalse(sameDay.isEligible)

        let data = try JSONEncoder().encode(progress)
        progress = try JSONDecoder().decode(CoreReviewProgress.self, from: data)
        progress.record(at: nextDay, calendar: calendar)
        XCTAssertTrue(progress.isEligible)
    }

    func testStitchCarriesToRowAtTarget() {
        let part = linked(stitchValue: 5)
        let result = Counting.increment(part, counterID: part.counters[1].id)
        XCTAssertEqual(result.part.row, 2); XCTAssertEqual(result.part.counters[1].value, 0)
        XCTAssertTrue(result.events.contains(.rowCompleted(1)))
    }
    func testMultilevelCarryAndRepeatEvent() {
        let group = Counter(name: "Repeat", kind: .repeatCount, value: 2)
        let row = Counter(name: "Row", value: 8, resetAt: 8, linkTo: group.id)
        let stitch = Counter(name: "Stitch", kind: .stitch, value: 5, min: 0, resetAt: 6, linkTo: row.id)
        let result = Counting.increment(Part(counters: [row, stitch, group]), counterID: stitch.id)
        XCTAssertEqual(result.part.counters.map(\.value), [1, 0, 3])
        XCTAssertTrue(result.events.contains(.patternRepeatDone(row.id)))
    }
    func testDecrementBorrowsPreviousRowsTarget() {
        var part = linked(rowValue: 2)
        part.roundTargets = [1: 12, 2: 18]
        let result = Counting.decrement(part, counterID: part.counters[1].id)
        XCTAssertEqual(result.part.row, 1); XCTAssertEqual(result.part.counters[1].value, 11)
    }
    func testCannotBorrowBelowMinimum() {
        let part = linked()
        XCTAssertEqual(Counting.decrement(part, counterID: part.counters[1].id).part, part)
    }
    func testMultilevelBorrow() {
        let group = Counter(name: "Repeat", kind: .repeatCount, value: 2)
        let row = Counter(name: "Row", value: 1, resetAt: 8, linkTo: group.id)
        let stitch = Counter(name: "Stitch", kind: .stitch, value: 0, min: 0, resetAt: 6, linkTo: row.id)
        let result = Counting.decrement(Part(counters: [row, stitch, group]), counterID: stitch.id)
        XCTAssertEqual(result.part.counters.map(\.value), [8, 5, 1])
    }
    func testTableOverridesResetAndAutomaticallyLinks() {
        var part = linked(stitchValue: 23)
        part.roundTargets = [1: 24, 2: 18]; part.counters[1].linkTo = nil
        let result = Counting.increment(part, counterID: part.counters[1].id)
        XCTAssertEqual(result.part.row, 2); XCTAssertEqual(result.part.counters[1].value, 0)
        XCTAssertEqual(Counting.target(for: result.part.counters[1], in: result.part), 18)
    }
    func testReminderOnlyOnArrival() {
        var part = linked(stitchValue: 5)
        let reminder = RowReminder(atRow: 2, text: "Change yarn", colorTag: 1); part.reminders = [reminder]
        let result = Counting.increment(part, counterID: part.counters[1].id)
        XCTAssertTrue(result.events.contains(.reminderHit(reminder)))
        XCTAssertFalse(Counting.increment(result.part, counterID: part.counters[1].id).events.contains(.reminderHit(reminder)))
    }
    func testUndoRestoresExactCountersAndTrackerAfterCarry() throws {
        var part = linked(stitchValue: 5); part.tracker.zoomScale = 2; part.tracker.offsetY = 0.3
        var stack: [UndoStep] = []; Counting.remember(part, in: &stack)
        let serialized = try JSONEncoder().encode(stack)
        stack = try JSONDecoder().decode([UndoStep].self, from: serialized)
        let updated = Counting.increment(part, counterID: part.counters[1].id).part
        XCTAssertEqual(Counting.undo(updated, stack: &stack), part)
    }
    func testUndoBoundedAtFifty() {
        var stack: [UndoStep] = []; let part = linked()
        for _ in 0..<80 { Counting.remember(part, in: &stack) }
        XCTAssertEqual(stack.count, 50)
    }
    func testOCRSnapsToMappedRowAcrossPages() {
        var part = linked(stitchValue: 5)
        part.patternPages = [PatternPage(ocrLines: [CGRect(x: 0, y: 0.15, width: 1, height: 0.05)], rowMap: [1: 0]), PatternPage(ocrLines: [CGRect(x: 0, y: 0.42, width: 1, height: 0.07)], rowMap: [2: 0])]
        let result = Counting.increment(part, counterID: part.counters[1].id)
        XCTAssertEqual(result.part.tracker.page, 1); XCTAssertEqual(result.part.tracker.y, 0.42, accuracy: 0.0001)
        XCTAssertEqual(result.part.tracker.height, 0.07, accuracy: 0.0001)
    }
    func testRingAndGridAdvance() {
        var part = linked(stitchValue: 5); part.tracker.mode = .ring
        let next = Counting.increment(part, counterID: part.counters[1].id).part
        XCTAssertEqual(next.tracker.radius, part.tracker.firstRadius + part.tracker.ringSpacing, accuracy: 0.0001)
        part.tracker.mode = .grid
        XCTAssertEqual(Counting.increment(part, counterID: part.counters[1].id).part.tracker.y, part.tracker.originY + part.tracker.cellHeight, accuracy: 0.0001)
    }
    func testDisabledLinksStillCountWithoutLosingExistingData() {
        let part = linked(stitchValue: 5)
        let result = Counting.increment(part, counterID: part.counters[1].id, linked: false)
        XCTAssertEqual(result.part.row, 1); XCTAssertEqual(result.part.counters[1].value, 6)
        XCTAssertEqual(result.part.counters[1].linkTo, part.counters[1].linkTo)
    }
    func testCycleTerminatesAndIntegerLimit() {
        var part = linked(stitchValue: 5); part.counters[0].resetAt = 1; part.counters[0].linkTo = part.counters[1].id
        XCTAssertEqual(Counting.increment(part, counterID: part.counters[1].id).part.counters.count, 2)
        part.counters[0].value = Counting.limit
        XCTAssertEqual(Counting.increment(part, counterID: part.counters[0].id).part.counters[0].value, Counting.limit)
    }
}
