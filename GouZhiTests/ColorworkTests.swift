import CoreImage
import XCTest

final class ColorworkTests: XCTestCase {
    func testStrokeFillsIntermediateCellsAndUndoRedoRestoreWholeStroke() throws {
        let blank = try XCTUnwrap(ColorworkChart(name: "Chart", width: 6, height: 4))
        var painted = blank
        let line = ChartCell(x: 0, y: 0).line(to: ChartCell(x: 5, y: 3))
        painted.paint(line, slot: 2)
        XCTAssertEqual(painted.cells.filter { $0 == 2 }.count, 6)
        XCTAssertEqual(painted.slot(x: 0, y: 0), 2)
        XCTAssertEqual(painted.slot(x: 5, y: 3), 2)
        painted.paint([ChartCell(x: 2, y: 1)], slot: 0)
        XCTAssertEqual(painted.slot(x: 2, y: 1), 0)
        var history = ChartEditHistory()
        history.record(blank)
        XCTAssertEqual(history.step(from: painted, backward: true), blank)
        XCTAssertEqual(history.step(from: blank, backward: false), painted)
        _ = history.step(from: painted, backward: true)
        history.record(blank)
        XCTAssertTrue(history.redo.isEmpty)
    }

    func testCopyRejectsOverflowAndAcceptsWholeBlockAtEdge() throws {
        var chart = try XCTUnwrap(ColorworkChart(name: "Chart", width: 4, height: 4))
        let source = ChartArea(from: .init(x: 1, y: 1), to: .init(x: 0, y: 0))
        let content: [UInt8] = [0, 1, 2, 3]
        XCTAssertTrue(chart.paste(content, in: source))
        let before = chart
        XCTAssertFalse(chart.paste(content, in: source.at(.init(x: 3, y: 2))))
        XCTAssertFalse(chart.paste([9, 2, 2, 2], in: source))
        XCTAssertEqual(chart, before)
        let edge = source.at(.init(x: 2, y: 2))
        XCTAssertTrue(chart.paste(try XCTUnwrap(chart.sample(source)), in: edge))
        XCTAssertEqual(chart.sample(edge), content)
        XCTAssertEqual(chart.sample(source), content)
    }

    func testOverlappingMoveAndBothMirrors() throws {
        var chart = try XCTUnwrap(ColorworkChart(name: "Chart", width: 3, height: 2, cells: [1, 2, 0, 3, 0, 1]))
        let source = ChartArea(from: .init(x: 0, y: 0), to: .init(x: 1, y: 1))
        let before = chart
        XCTAssertFalse(chart.move(source, to: .init(x: 2, y: 0)))
        XCTAssertEqual(chart, before)
        let origin = ChartCell(x: 1, y: 0)
        XCTAssertTrue(chart.move(source, to: origin))
        XCTAssertEqual(chart.cells, [0, 1, 2, 0, 3, 0])
        chart.mirror(source.at(origin), horizontal: true)
        XCTAssertEqual(chart.cells, [0, 2, 1, 0, 0, 3])
        chart.mirror(source.at(origin), horizontal: false)
        XCTAssertEqual(chart.cells, [0, 0, 3, 0, 2, 1])
    }

    func testQuantizerKeepsTwoDistinctColorsAndUsesRequestedLimit() throws {
        let red = ChartSwatch(255, 0, 0), blue = ChartSwatch(0, 0, 255), green = ChartSwatch(0, 255, 0)
        let chart = try XCTUnwrap(ChartQuantizer.chart(name: "Chart", width: 2, height: 2,
                                                       pixels: [red, blue, red, blue], colorCount: 8))
        XCTAssertEqual(Set(chart.palette), Set([red, blue]))
        XCTAssertEqual(chart.palette[Int(chart.slot(x: 0, y: 0)) - 1], red)
        XCTAssertEqual(chart.palette[Int(chart.slot(x: 1, y: 0)) - 1], blue)
        XCTAssertEqual(ChartQuantizer.chart(name: "Chart", width: 3, height: 1,
                                          pixels: [red, blue, green], colorCount: 2)?.palette.count, 2)
        XCTAssertNil(ChartQuantizer.chart(name: "Chart", width: 61, height: 1, pixels: [], colorCount: 2))
    }

    func testCoreImageDownsamplePreservesTopToBottomOrder() throws {
        let bounds = CGRect(x: 0, y: 0, width: 16, height: 16)
        let blue = CIImage(color: CIColor(red: 0, green: 0, blue: 1)).cropped(to: bounds)
        let red = CIImage(color: CIColor(red: 1, green: 0, blue: 0))
            .cropped(to: CGRect(x: 0, y: 8, width: 16, height: 8))
        let chart = try XCTUnwrap(ColorworkImage.chart(from: red.composited(over: blue),
                                                       name: "Chart", width: 2, height: 4, colorCount: 2))
        let top = chart.palette[Int(chart.slot(x: 0, y: 0)) - 1]
        let bottom = chart.palette[Int(chart.slot(x: 0, y: 3)) - 1]
        XCTAssertGreaterThan(top.red, top.blue)
        XCTAssertGreaterThan(bottom.blue, bottom.red)
        XCTAssertEqual(chart.palette.count, 2)
    }

    func testReadDirectionsStartingEdgesAndRowMapping() throws {
        let chart = try XCTUnwrap(ColorworkChart(name: "Chart", width: 2, height: 4))
        XCTAssertEqual(chart.gridRow(for: 1), 3)
        XCTAssertEqual(chart.gridRow(for: 4), 0)
        XCTAssertNil(chart.gridRow(for: 0))
        XCTAssertNil(chart.gridRow(for: 5))
        XCTAssertTrue(ChartReading.flat.startsAtRight(row: 1))
        XCTAssertFalse(ChartReading.flat.startsAtRight(row: 2))
        XCTAssertTrue(ChartReading.round.startsAtRight(row: 2))
        XCTAssertFalse(ChartReading.round.startsAtRight(row: 2, firstAtRight: false))
        XCTAssertTrue(ChartReading.flat.startsAtRight(row: 2, firstAtRight: false))
    }

    func testTilingRepeatAndSharedStitchPositionsAcrossColorways() throws {
        var chart = try XCTUnwrap(ColorworkChart(name: "Chart", width: 2, height: 2, cells: [0, 1, 2, 3]))
        chart.colorways.append(Array(chart.palette.reversed()))
        chart.activeColorway = 1
        chart.tile(across: 2, down: 2)
        XCTAssertEqual(chart.width, 4)
        XCTAssertEqual(chart.height, 4)
        XCTAssertEqual(chart.cells, [0, 1, 0, 1, 2, 3, 2, 3, 0, 1, 0, 1, 2, 3, 2, 3])
        XCTAssertEqual(chart.palette, chart.colorways[1])
        let tiled = chart
        chart.tile(across: 16, down: 1)
        XCTAssertEqual(chart, tiled)
    }

    func testExchangeRoundTripWithNewIdentityAndOldProjectsDecode() throws {
        var chart = try XCTUnwrap(ColorworkChart(name: "Chart", width: 60, height: 60))
        chart.paint([.init(x: 59, y: 59)], slot: 3)
        chart.gauge = .init(stitches: 22, rows: 28)
        chart.reading = .round
        chart.firstAtRight = false
        let file = try XCTUnwrap(ColorworkExchange.file(for: chart))
        let code = try XCTUnwrap(ColorworkExchange.code(for: chart))
        for imported in [ColorworkExchange.read(file), ColorworkExchange.readCode("Sample " + code)] {
            var copy = try XCTUnwrap(imported)
            XCTAssertNotEqual(copy.id, chart.id)
            copy.id = chart.id
            XCTAssertEqual(copy, chart)
        }
        XCTAssertNil(ColorworkExchange.readCode("CW1:invalid"))
        XCTAssertNil(ColorworkExchange.read(Data(repeating: 0, count: ColorworkExchange.maxFileBytes + 1)))
        let old = try JSONDecoder().decode(Project.self, from: Data(#"{"name":"Old","parts":[{}]}"#.utf8))
        XCTAssertTrue(old.colorworkCharts.isEmpty)
        XCTAssertNil(old.part.activeColorworkID)
        var project = old
        project.colorworkCharts = [chart]
        project.parts[0].activeColorworkID = chart.id
        let restored = try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(project))
        XCTAssertEqual(restored, project)
    }
}
