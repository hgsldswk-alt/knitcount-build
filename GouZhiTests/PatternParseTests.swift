import XCTest

final class PatternParseTests: XCTestCase {
    func testChineseRangeAndFullWidthTarget() {
        let lines = PatternParse.lines("第 18–20 圈：每圈36针（36）\n第21行：短针 (30 sts)\n第22轮：每针1针（24针）")
        XCTAssertEqual(lines.compactMap(\.row), [18, 19, 20, 21, 22])
        XCTAssertEqual(PatternParse.targets(lines), [18: 36, 19: 36, 20: 36, 21: 30, 22: 24])
    }
    func testOtherRangeSeparatorsAndEnglish() {
        for separator in ["-", "–", "~", "至", "到"] { XCTAssertEqual(PatternParse.lines("第1" + separator + "3圈（12）").count, 3) }
        let lines = PatternParse.lines("Rnd 1: sc (6)\nRow 2–3: dc (12 stitches)\nr4: hdc (18 st)\nROUND 5: sc (24)")
        XCTAssertEqual(lines.compactMap(\.row), [1, 2, 3, 4, 5]); XCTAssertEqual(lines.last?.target, 24)
    }
    func testJapaneseRows() {
        let lines = PatternParse.lines("18〜20段：細編みで1周（36）\n21段目：細編み（30目）\n第22段 細編み（24）\n6目離して安全目を付ける\n目標：約 5 目 × 6 段")
        XCTAssertEqual(lines.compactMap(\.row), [18, 19, 20, 21, 22])
        XCTAssertEqual(PatternParse.targets(lines), [18: 36, 19: 36, 20: 36, 21: 30, 22: 24])
        XCTAssertNil(lines[5].row); XCTAssertNil(lines[6].row)
    }
    func testLastParenthesisOnlyAndNonRowText() {
        let lines = PatternParse.lines("第6圈：(2短针, 1加针) ×6（24）\n填充棉花\n第7圈：(30) 说明")
        XCTAssertEqual(lines[0].target, 24); XCTAssertNil(lines[1].row); XCTAssertNil(lines[2].target)
    }
    func testSizeRangesForEveryOccurrenceAndUnicode() {
        let text = "🧶 胸围36 (40, 44, 48)，袖口18(20,22,24)，S(M, L, XL)"
        XCTAssertEqual(PatternParse.sizeRanges(in: text, sizeIndex: 1).map { String(text[$0]) }, ["40", "20", "M"])
        XCTAssertEqual(PatternParse.sizeRanges(in: text, sizeIndex: 0).map { String(text[$0]) }, ["36", "18", "S"])
        XCTAssertTrue(PatternParse.sizeRanges(in: text, sizeIndex: 9).isEmpty)
    }
    func testVideoTimeLinksReplaceExistingTimestamp() {
        XCTAssertEqual(PatternParse.videoURL("https://www.bilibili.com/video/abc?t=9&p=2", seconds: 201)?.absoluteString, "https://www.bilibili.com/video/abc?p=2&t=201")
        XCTAssertEqual(PatternParse.videoURL("https://www.youtube.com/watch?v=abc", seconds: 201)?.absoluteString, "https://www.youtube.com/watch?v=abc&t=201s")
        XCTAssertEqual(PatternParse.videoURL("https://example.com/video?a=1", seconds: 201)?.absoluteString, "https://example.com/video?a=1")
        XCTAssertNil(PatternParse.videoURL("javascript:alert(1)", seconds: 0))
        XCTAssertEqual(PatternParse.seconds("03:21"), 201); XCTAssertNil(PatternParse.seconds("03:99"))
    }
}
