import Foundation

struct ChartCell: Equatable {
    var x: Int
    var y: Int

    func line(to end: Self) -> [Self] {
        let dx = abs(end.x - x), dy = abs(end.y - y)
        let stepX = x < end.x ? 1 : -1, stepY = y < end.y ? 1 : -1
        var point = self, error = dx - dy, cells = [self]
        while point != end {
            let twice = 2 * error
            if twice > -dy { error -= dy; point.x += stepX }
            if twice < dx { error += dx; point.y += stepY }
            cells.append(point)
        }
        return cells
    }
}

struct ChartArea: Equatable {
    var origin: ChartCell
    var width: Int
    var height: Int

    init(from a: ChartCell, to b: ChartCell) {
        origin = ChartCell(x: min(a.x, b.x), y: min(a.y, b.y))
        width = abs(a.x - b.x) + 1
        height = abs(a.y - b.y) + 1
    }

    func at(_ origin: ChartCell) -> Self {
        ChartArea(from: origin, to: ChartCell(x: origin.x + width - 1, y: origin.y + height - 1))
    }
}

struct ChartSwatch: Codable, Equatable, Hashable {
    let red: UInt8
    let green: UInt8
    let blue: UInt8

    init(_ red: UInt8, _ green: UInt8, _ blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    var hex: String { String(format: "#%02X%02X%02X", Int(red), Int(green), Int(blue)) }

    func distance(to other: Self) -> Int {
        let r = Int(red) - Int(other.red), g = Int(green) - Int(other.green), b = Int(blue) - Int(other.blue)
        return r * r + g * g + b * b
    }
}

enum ChartReading: String, Codable, CaseIterable {
    case flat, round

    func startsAtRight(row: Int, firstAtRight: Bool = true) -> Bool {
        self == .flat && row.isMultiple(of: 2) ? !firstAtRight : firstAtRight
    }
}

struct ColorworkChart: Codable, Equatable, Identifiable {
    static let maxSide = 60
    static let maxColors = 8
    static let maxColorways = 4
    static let presets: [ChartSwatch] = [
        .init(243, 232, 210), .init(181, 82, 59), .init(189, 135, 80),
        .init(48, 100, 107), .init(65, 82, 68), .init(103, 76, 114),
        .init(61, 58, 59), .init(189, 120, 138), .init(84, 98, 117), .init(255, 255, 255)
    ]

    struct Gauge: Codable, Equatable {
        var stitches: Double
        var rows: Double
        var valid: Bool { (0.5...200).contains(stitches) && (0.5...200).contains(rows) }
    }

    var id = UUID()
    var name: String
    private(set) var width: Int
    private(set) var height: Int
    private(set) var cells: [UInt8]
    var colorways: [[ChartSwatch]]
    var activeColorway = 0
    var reading: ChartReading = .flat
    var firstAtRight = true
    var gauge: Gauge?

    init?(name: String, width: Int, height: Int, colors: [ChartSwatch] = Array(ColorworkChart.presets.prefix(3)), cells: [UInt8]? = nil) {
        guard Self.validSize(width, height) else { return nil }
        self.name = name
        self.width = width
        self.height = height
        self.cells = cells ?? Array(repeating: 0, count: width * height)
        colorways = [colors]
        guard valid else { return nil }
    }

    static func validSize(_ width: Int, _ height: Int) -> Bool {
        (1...maxSide).contains(width) && (1...maxSide).contains(height)
    }

    var valid: Bool {
        guard Self.validSize(width, height), name.utf8.count <= 400, cells.count == width * height,
              (1...Self.maxColorways).contains(colorways.count), colorways.indices.contains(activeColorway),
              let first = colorways.first, (1...Self.maxColors).contains(first.count),
              colorways.allSatisfy({ $0.count == first.count }),
              cells.allSatisfy({ Int($0) <= first.count }), gauge?.valid != false else { return false }
        return true
    }

    var palette: [ChartSwatch] { colorways[activeColorway] }
    var cellAspect: Double { gauge.map { $0.rows / $0.stitches } ?? 1 }

    func contains(_ cell: ChartCell) -> Bool {
        (0..<width).contains(cell.x) && (0..<height).contains(cell.y)
    }

    func fits(_ area: ChartArea) -> Bool {
        contains(area.origin) && area.width <= width - area.origin.x && area.height <= height - area.origin.y
    }

    func gridRow(for row: Int) -> Int? {
        (1...height).contains(row) ? height - row : nil
    }

    func slot(x: Int, y: Int) -> UInt8 { cells[y * width + x] }

    mutating func paint(_ points: [ChartCell], slot: UInt8) {
        guard Int(slot) <= palette.count else { return }
        for point in points where contains(point) { cells[point.y * width + point.x] = slot }
    }

    func sample(_ area: ChartArea) -> [UInt8]? {
        guard fits(area) else { return nil }
        return (0..<area.height).flatMap { y in
            let start = (area.origin.y + y) * width + area.origin.x
            return cells[start..<(start + area.width)]
        }
    }

    @discardableResult
    mutating func paste(_ content: [UInt8], in area: ChartArea) -> Bool {
        guard fits(area), content.count == area.width * area.height,
              content.allSatisfy({ Int($0) <= palette.count }) else { return false }
        for y in 0..<area.height {
            let start = (area.origin.y + y) * width + area.origin.x
            let source = y * area.width
            cells.replaceSubrange(start..<(start + area.width), with: content[source..<(source + area.width)])
        }
        return true
    }

    @discardableResult
    mutating func move(_ area: ChartArea, to origin: ChartCell) -> Bool {
        let destination = area.at(origin)
        guard fits(destination), let content = sample(area) else { return false }
        paste(Array(repeating: 0, count: content.count), in: area)
        return paste(content, in: destination)
    }

    mutating func mirror(_ area: ChartArea, horizontal: Bool) {
        guard let content = sample(area) else { return }
        let mirrored = content.indices.map { index in
            let x = index % area.width, y = index / area.width
            return horizontal ? content[y * area.width + area.width - 1 - x]
                              : content[(area.height - 1 - y) * area.width + x]
        }
        paste(mirrored, in: area)
    }

    mutating func tile(across: Int, down: Int) {
        guard (1...Self.maxSide / width).contains(across), (1...Self.maxSide / height).contains(down) else { return }
        let original = self
        width *= across
        height *= down
        cells = (0..<(width * height)).map { original.slot(x: ($0 % width) % original.width, y: ($0 / width) % original.height) }
    }
}

struct ChartEditHistory {
    private(set) var undo: [ColorworkChart] = []
    private(set) var redo: [ColorworkChart] = []

    mutating func record(_ previous: ColorworkChart) {
        undo.append(previous)
        if undo.count > 50 { undo.removeFirst() }
        redo.removeAll()
    }

    mutating func step(from chart: ColorworkChart, backward: Bool) -> ColorworkChart? {
        if backward {
            guard let previous = undo.popLast() else { return nil }
            redo.append(chart)
            return previous
        }
        guard let next = redo.popLast() else { return nil }
        undo.append(chart)
        return next
    }
}

enum ChartQuantizer {
    static func chart(name: String, width: Int, height: Int, pixels: [ChartSwatch], colorCount: Int) -> ColorworkChart? {
        guard ColorworkChart.validSize(width, height), (2...8).contains(colorCount), pixels.count == width * height,
              let first = pixels.first else { return nil }

        let average = mean(pixels)
        var palette = [pixels.min(by: { $0.distance(to: average) < $1.distance(to: average) }) ?? first]
        var distances = pixels.map { $0.distance(to: palette[0]) }
        while palette.count < colorCount, let next = distances.indices.max(by: { distances[$0] < distances[$1] }),
              distances[next] > 0 {
            let color = pixels[next]
            palette.append(color)
            distances = pixels.indices.map { min(distances[$0], pixels[$0].distance(to: color)) }
        }
        for _ in 0..<10 {
            var groups = Array(repeating: [ChartSwatch](), count: palette.count)
            for pixel in pixels { groups[nearest(pixel, in: palette)].append(pixel) }
            let next = groups.enumerated().map { $0.element.isEmpty ? palette[$0.offset] : mean($0.element) }
            if next == palette { break }
            palette = next
        }
        let slots = pixels.map { UInt8(nearest($0, in: palette) + 1) }
        return ColorworkChart(name: name, width: width, height: height, colors: palette, cells: slots)
    }

    private static func nearest(_ color: ChartSwatch, in palette: [ChartSwatch]) -> Int {
        palette.indices.min { color.distance(to: palette[$0]) < color.distance(to: palette[$1]) } ?? 0
    }

    private static func mean(_ pixels: [ChartSwatch]) -> ChartSwatch {
        let sum = pixels.reduce(into: (r: 0, g: 0, b: 0)) { sum, pixel in
            sum.r += Int(pixel.red)
            sum.g += Int(pixel.green)
            sum.b += Int(pixel.blue)
        }
        let count = pixels.count
        return ChartSwatch(UInt8(sum.r / count), UInt8(sum.g / count), UInt8(sum.b / count))
    }
}
