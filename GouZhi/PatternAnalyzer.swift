import UIKit
import Vision
import PDFKit

struct PatternAnalysis {
    var text: String = ""
    var boxes: [CGRect] = []
    var rowMap: [Int: Int] = [:]
    var targets: [Int: Int] = [:]
    var grid: CGSize?
}
enum PatternAnalyzer {
    static func analyze(_ image: UIImage, pdfPage: PDFPage? = nil) -> PatternAnalysis {
        if let page = pdfPage, let selection = page.selection(for: page.bounds(for: .mediaBox)), !selection.string.orEmpty.isEmpty {
            let pageBounds = page.bounds(for: .mediaBox)
            let lines = selection.selectionsByLine().compactMap { line -> (String, CGRect)? in
                guard let text = line.string, !text.isEmpty else { return nil }
                let b = line.bounds(for: page)
                return (text, CGRect(x: (b.minX - pageBounds.minX) / pageBounds.width,
                                     y: 1 - (b.maxY - pageBounds.minY) / pageBounds.height,
                                     width: b.width / pageBounds.width, height: b.height / pageBounds.height))
            }
            if !lines.isEmpty { return combine(lines, grid: grayscale(image).flatMap(grid)) }
        }
        guard let cg = image.cgImage else { return PatternAnalysis() }
        let request = VNRecognizeTextRequest()
        request.recognitionLanguages = ["zh-Hans", "en-US"]; request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        do { try VNImageRequestHandler(cgImage: cg, options: [:]).perform([request]) }
        catch { return PatternAnalysis() }
        let lines = (request.results ?? []).compactMap { observation -> (String, CGRect)? in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            let b = observation.boundingBox
            return (text, CGRect(x: b.minX, y: 1 - b.maxY, width: b.width, height: b.height))
        }
        return combine(lines, grid: grayscale(image).flatMap(grid))
    }
    private static func combine(_ input: [(String, CGRect)], grid: CGSize?) -> PatternAnalysis {
        let sorted = input.sorted { abs($0.1.midY - $1.1.midY) < 0.008 ? $0.1.minX < $1.1.minX : $0.1.midY < $1.1.midY }
        var merged: [(String, CGRect)] = []
        for line in sorted {
            if let last = merged.last, abs(last.1.midY - line.1.midY) < min(last.1.height, line.1.height) * 0.45 {
                merged[merged.count - 1] = (last.0 + " " + line.0, last.1.union(line.1))
            } else { merged.append(line) }
        }
        var result = PatternAnalysis(text: merged.map { $0.0 }.joined(separator: "\n"), boxes: merged.map { $0.1 }, grid: grid)
        for (i, line) in merged.enumerated() {
            for parsed in PatternParse.lines(line.0) {
                if let row = parsed.row { result.rowMap[row] = i; if let target = parsed.target { result.targets[row] = target } }
            }
        }
        return result
    }
    private struct Gray { var pixels: [UInt8]; var size: Int }
    private static func grayscale(_ image: UIImage) -> Gray? {
        guard let cg = image.cgImage else { return nil }
        let n = 256; var pixels = [UInt8](repeating: 255, count: n * n)
        let ok = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n,
                                          space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: n, height: n)); return true
        }
        return ok ? Gray(pixels: pixels, size: n) : nil
    }
    private static func spacing(_ values: [Double]) -> Double? {
        guard let peak = values.max(), peak > 0.12 else { return nil }
        var peaks: [Int] = []
        for i in 1..<(values.count - 1) where values[i] > peak * 0.7 && values[i] >= values[i - 1] && values[i] > values[i + 1] {
            if let last = peaks.last, i - last < 3 { continue }; peaks.append(i)
        }
        guard peaks.count >= 4 else { return nil }
        let gaps = zip(peaks.dropFirst(), peaks).map { $0 - $1 }.sorted()
        let median = gaps[gaps.count / 2]
        guard median >= 3, gaps.filter({ abs($0 - median) <= 2 }).count * 4 >= gaps.count * 3 else { return nil }
        return Double(median) / Double(values.count)
    }
    private static func grid(_ gray: Gray) -> CGSize? {
        let n = gray.size
        var rows = [Double](repeating: 0, count: n), columns = rows
        for y in 0..<n { for x in 0..<n {
            let dark = (255 - Double(gray.pixels[y * n + x])) / (255 * Double(n))
            rows[y] += dark; columns[x] += dark
        } }
        guard let w = spacing(columns), let h = spacing(rows) else { return nil }
        return CGSize(width: w, height: h)
    }
    static func ringSpacing(_ image: UIImage, center: CGPoint) -> Double? {
        guard let gray = grayscale(image) else { return nil }
        let n = gray.size, length = 100
        var votes: [Double] = []
        for direction in 0..<8 {
            let angle = Double(direction) * .pi / 4
            var values: [Double] = []
            for r in 0..<length {
                let x = Int(center.x * Double(n) + cos(angle) * Double(r))
                let y = Int(center.y * Double(n) + sin(angle) * Double(r))
                guard (0..<n).contains(x), (0..<n).contains(y) else { break }
                values.append((255 - Double(gray.pixels[y * n + x])) / 255)
            }
            if values.count > 20, let period = spacing(values) { votes.append(period * Double(values.count) / Double(n)) }
        }
        guard votes.count >= 3 else { return nil }
        votes.sort(); let median = votes[votes.count / 2]
        return votes.filter({ abs($0 - median) < 0.015 }).count >= 3 ? median : nil
    }
}
private extension Optional where Wrapped == String { var orEmpty: String { self ?? "" } }
