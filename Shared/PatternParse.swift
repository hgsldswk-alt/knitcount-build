import Foundation

enum PatternParse {
    private static let rowPattern = #"(?:第\s*(\d+)(?:\s*[-–~至到]\s*(\d+))?\s*(?:圈|行|轮|段)|\bR(?:ow|nd|ound)?\s*(\d+)(?:\s*[-–]\s*(\d+))?|(\d+)(?:\s*[-–~〜]\s*(\d+))?\s*段(?:目|\s*[:：]))"#  // 11-26 加日文「第N段」「N段目」「N〜M段：」
    static func lines(_ text: String) -> [PatternLine] {
        let rowRE = try! NSRegularExpression(pattern: rowPattern, options: .caseInsensitive)
        let targetRE = try! NSRegularExpression(pattern: #"[（(]\s*(\d+)\s*(?:针|目|sts?|stitches)?\s*[)）]\s*[。.!]?\s*$"#, options: .caseInsensitive)
        var result: [PatternLine] = []
        for raw in text.components(separatedBy: .newlines) {
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let range = NSRange(text.startIndex..., in: text)
            let target = targetRE.matches(in: text, range: range).last.flatMap { number(text, $0.range(at: 1)) }
            if let match = rowRE.firstMatch(in: text, range: range),
               let start = number(text, match.range(at: 1)) ?? number(text, match.range(at: 3)) ?? number(text, match.range(at: 5)), (1...100_000).contains(start) {
                let end = number(text, match.range(at: 2)) ?? number(text, match.range(at: 4)) ?? number(text, match.range(at: 6)) ?? start
                let safeEnd = min(100_000, min(start + 1000, max(start, end)))
                for row in start...safeEnd { result.append(PatternLine(text: text, row: row, target: target)) }
            } else { result.append(PatternLine(text: text, target: target)) }
            if result.count >= 20_000 { break }
        }
        return result
    }
    private static func number(_ text: String, _ range: NSRange) -> Int? {
        guard range.location != NSNotFound, let r = Range(range, in: text) else { return nil }
        return Int(text[r])
    }
    static func targets(_ lines: [PatternLine]) -> [Int: Int] {
        lines.reduce(into: [:]) { table, line in
            if let row = line.row, let target = line.target, target > 0, target <= Counting.limit { table[row] = target }
        }
    }
    static func sizeRanges(in text: String, sizeIndex: Int) -> [Range<String.Index>] {
        guard (0...15).contains(sizeIndex) else { return [] }
        let re = try! NSRegularExpression(pattern: #"(?:\d+|[A-Za-z]+)\s*[（(]\s*(?:\d+|[A-Za-z]+)(?:\s*[,，]\s*(?:\d+|[A-Za-z]+))+\s*[)）]"#)
        let token = try! NSRegularExpression(pattern: #"\d+|[A-Za-z]+"#)
        return re.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            let tokens = token.matches(in: text, range: match.range)
            guard tokens.indices.contains(sizeIndex) else { return nil }
            return Range(tokens[sizeIndex].range, in: text)
        }
    }
    static func videoURL(_ raw: String, seconds: Int) -> URL? {
        guard var c = URLComponents(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = c.scheme?.lowercased(), ["https", "http"].contains(scheme), let host = c.host?.lowercased() else { return nil }
        let isBili = host == "bilibili.com" || host.hasSuffix(".bilibili.com") || host == "b23.tv"
        let isYouTube = host == "youtube.com" || host.hasSuffix(".youtube.com") || host == "youtu.be"
        guard isBili || isYouTube else { return c.url }
        var items = (c.queryItems ?? []).filter { $0.name != "t" }
        items.append(URLQueryItem(name: "t", value: String(max(0, seconds)) + (isYouTube ? "s" : "")))
        c.queryItems = items; return c.url
    }
    static func seconds(_ text: String) -> Int? {
        let parts = text.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, parts[0] >= 0, (0..<60).contains(parts[1]), parts[0] <= 100_000 else { return nil }
        return parts[0] * 60 + parts[1]
    }
    static func name(from text: String, now: Date = Date()) -> String {
        if let line = text.components(separatedBy: .newlines).first(where: { $0.trimmingCharacters(in: .whitespaces).count >= 2 }) {
            return String(line.trimmingCharacters(in: .whitespaces).prefix(12))
        }
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("MMMd")
        return L.f("作品 %@", f.string(from: now))
    }
}
