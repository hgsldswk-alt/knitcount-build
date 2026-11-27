import Foundation
import XCTest

final class KnittingCalculatorTests: XCTestCase {
    func testYarnRoundsDownAndAppliesReserve() {
        XCTAssertEqual(YarnEstimate.rows(before: 50, after: 42, worked: 5, reserve: 3), 24)
        XCTAssertEqual(YarnEstimate.rows(before: 20, after: 10, worked: 5, reserve: 2), 4)
        XCTAssertEqual(YarnEstimate.rows(before: 20, after: 10, worked: 5, reserve: 10), 0)
        XCTAssertEqual(YarnEstimate.rows(before: 20, after: 10, worked: 5, reserve: 12), 0)
        XCTAssertEqual(YarnEstimate.rows(before: 20, after: 0, worked: 5, reserve: 0), 0)
        XCTAssertEqual(YarnEstimate.rows(before: Decimal(string: "1.2")!, after: Decimal(string: "0.9")!,
                                        worked: 1, reserve: 0), 3)
    }

    func testYarnRejectsInvalidOrOutOfRangeValues() {
        XCTAssertNil(YarnEstimate.rows(before: 20, after: 10, worked: 0, reserve: 0))
        XCTAssertNil(YarnEstimate.rows(before: 20, after: 10, worked: -2, reserve: 0))
        XCTAssertNil(YarnEstimate.rows(before: 20, after: 10, worked: 2, reserve: -1))
        XCTAssertNil(YarnEstimate.rows(before: 20, after: -10, worked: 2, reserve: 0))
        XCTAssertNil(YarnEstimate.rows(before: -20, after: 10, worked: 2, reserve: 0))
        XCTAssertNil(YarnEstimate.rows(before: 10, after: 10, worked: 2, reserve: 0))
        XCTAssertNil(YarnEstimate.rows(before: 9, after: 10, worked: 2, reserve: 0))
        XCTAssertNil(YarnEstimate.rows(before: 100, after: 99, worked: Int.max, reserve: 0))
    }

    func testYarnUnitsAndPatternComparison() throws {
        let metre = try XCTUnwrap(YarnUnit.yards.convert(10_000, to: .metres))
        XCTAssertEqual(metre, 9144)
        XCTAssertEqual(YarnUnit.metres.convert(metre, to: .yards), 10_000)
        XCTAssertNil(YarnUnit.grams.convert(42, to: .yards))
        XCTAssertNil(YarnUnit.metres.convert(42, to: .grams))
        let before = try XCTUnwrap(YarnUnit.yards.convert(35, to: .metres))
        let after = try XCTUnwrap(YarnUnit.yards.convert(30, to: .metres))
        let reserve = try XCTUnwrap(YarnUnit.yards.convert(5, to: .metres))
        XCTAssertEqual(YarnEstimate.rows(before: before, after: after, worked: 4, reserve: reserve), 20)
        XCTAssertEqual(YarnEstimate.remainingRows(lastRow: 38, currentRow: 23), 16)
        XCTAssertEqual(YarnEstimate.remainingRows(lastRow: 38, currentRow: 38), 1)
        XCTAssertEqual(YarnEstimate.remainingRows(lastRow: 38, currentRow: 39), 0)
        XCTAssertNil(YarnEstimate.remainingRows(lastRow: 0, currentRow: 23))
        XCTAssertEqual(YarnEstimate.fit(available: 16, remaining: 16), .enough)
        XCTAssertEqual(YarnEstimate.fit(available: 12, remaining: 16), .short(4))
        XCTAssertNil(YarnEstimate.fit(available: 12, remaining: nil))
    }

    private func gauge() -> GaugeRecord {
        GaugeRecord(unit: .centimetres,
                    before: GaugePair(across: 20, down: 30), after: GaugePair(across: 16, down: 24),
                    currentKind: .size, current: GaugePair(across: 40, down: 50),
                    target: GaugePair(across: 50, down: 30))
    }

    func testGaugeUsesBothAxesAndBothCurrentInputModes() throws {
        var record = gauge()
        XCTAssertEqual(GaugeCalculator.blockedSize(record), GaugePair(across: 50, down: 62.5))
        let target = try XCTUnwrap(GaugeCalculator.targetCounts(record))
        XCTAssertEqual(target.stitches, 80)
        XCTAssertEqual(target.rows, 72)
        record.currentKind = .counts
        record.current = GaugePair(across: 80, down: 150)
        XCTAssertEqual(GaugeCalculator.blockedSize(record), GaugePair(across: 50, down: 62.5))
        record.current = GaugePair(across: 80.5, down: 150)
        XCTAssertNil(GaugeCalculator.blockedSize(record))
    }

    func testGaugeInchesUseActualFourInchSpan() throws {
        let source = gauge()
        let cm = GaugeUnit.centimetres, inch = GaugeUnit.inches
        XCTAssertEqual(inch.convert(4, to: cm), 10.16, accuracy: 0.000001)
        XCTAssertEqual(cm.convert(2.54, to: inch), 1, accuracy: 0.000001)
        XCTAssertEqual(cm.convertSwatchCount(20, to: inch), 20.32, accuracy: 0.000001)

        var record = source
        record.unit = inch
        record.before = GaugePair(across: 20.32, down: 30.48)
        record.after = GaugePair(across: 16.256, down: 24.384)
        record.currentKind = .counts
        record.current = GaugePair(across: 80, down: 150)
        record.target = GaugePair(across: cm.convert(50, to: inch), down: cm.convert(30, to: inch))
        let size = try XCTUnwrap(GaugeCalculator.blockedSize(record))
        XCTAssertEqual(inch.convert(size.across, to: cm), 50, accuracy: 0.000001)
        XCTAssertEqual(inch.convert(size.down, to: cm), 62.5, accuracy: 0.000001)
        let target = try XCTUnwrap(GaugeCalculator.targetCounts(record))
        XCTAssertEqual(target.stitches, 80)
        XCTAssertEqual(target.rows, 72)
    }

    func testGaugeInvalidCountsSizesAndOverflow() throws {
        var record = gauge()
        record.before.down = 0
        XCTAssertNil(GaugeCalculator.blockedSize(record))
        XCTAssertNil(GaugeCalculator.targetCounts(record))
        record = gauge()
        record.after.across = -1
        XCTAssertNil(GaugeCalculator.blockedSize(record))
        record = gauge()
        record.current = GaugePair(across: .infinity, down: 40)
        record.target = GaugePair(across: 0, down: 1)
        XCTAssertNil(GaugeCalculator.blockedSize(record))
        XCTAssertNil(GaugeCalculator.targetCounts(record))
        record.target = GaugePair(across: -1, down: 1)
        XCTAssertNil(GaugeCalculator.targetCounts(record))
        record.target = GaugePair(across: .greatestFiniteMagnitude, down: 1)
        XCTAssertNil(GaugeCalculator.targetCounts(record))
        record.after = GaugePair(across: 10, down: 10)
        record.target = GaugePair(across: 4.5, down: 0.2)
        let target = try XCTUnwrap(GaugeCalculator.targetCounts(record))
        XCTAssertEqual(target.stitches, 5)
        XCTAssertEqual(target.rows, 1)
    }

    func testGaugeIsOptionalForOldProjectsAndRoundTrips() throws {
        var project = try JSONDecoder().decode(Project.self, from: Data("{}".utf8))
        XCTAssertNil(project.gauge)
        project.gauge = gauge()
        let restored = try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(project))
        XCTAssertEqual(restored.gauge, project.gauge)
        XCTAssertEqual(GaugeCalculator.blockedSize(try XCTUnwrap(restored.gauge)), GaugePair(across: 50, down: 62.5))
    }
}
