import Foundation

enum YarnUnit: String, CaseIterable {
    case grams, metres, yards

    func convert(_ value: Decimal, to unit: YarnUnit) -> Decimal? {
        if self == unit { return value }
        guard self != .grams, unit != .grams else { return nil }
        let metresPerYard = Decimal(9144) / Decimal(10_000)
        return self == .yards ? value * metresPerYard : value / metresPerYard
    }
}

enum YarnEstimate {
    enum Fit: Equatable {
        case enough, short(Int)
    }

    static func rows(before: Decimal, after: Decimal, worked: Int, reserve: Decimal) -> Int? {
        guard !before.isNaN, !after.isNaN, !reserve.isNaN,
              before > after, after >= 0, reserve >= 0, worked > 0 else { return nil }
        if after <= reserve { return 0 }

        var estimate = (after - reserve) * Decimal(worked) / (before - after)
        guard !estimate.isNaN else { return nil }
        var whole = Decimal()
        NSDecimalRound(&whole, &estimate, 0, .down)
        return Int(NSDecimalNumber(decimal: whole).stringValue)
    }

    static func fit(available: Int, remaining: Int?) -> Fit? {
        guard available >= 0, let remaining, remaining >= 0 else { return nil }
        return available >= remaining ? .enough : .short(remaining - available)
    }

    static func remainingRows(lastRow: Int, currentRow: Int) -> Int? {
        guard lastRow > 0, currentRow >= 0 else { return nil }
        return max(0, lastRow - max(0, currentRow - 1))
    }
}

enum GaugeUnit: String, Codable, CaseIterable {
    case centimetres, inches

    var swatchSpan: Double { self == .centimetres ? 10 : 4 }
    private var centimetresPerUnit: Double { self == .centimetres ? 1 : 2.54 }

    func convert(_ length: Double, to unit: GaugeUnit) -> Double {
        if self == unit { return length }
        return length * centimetresPerUnit / unit.centimetresPerUnit
    }

    func convertSwatchCount(_ count: Double, to unit: GaugeUnit) -> Double {
        count * (unit.convert(unit.swatchSpan, to: self) / swatchSpan)
    }
}

enum GaugeInputKind: String, Codable, CaseIterable {
    case size, counts
}

struct GaugePair: Codable, Equatable {
    var across: Double
    var down: Double

    var isPositive: Bool { across.isFinite && down.isFinite && across > 0 && down > 0 }
}

struct GaugeRecord: Codable, Equatable {
    var unit: GaugeUnit
    var before: GaugePair
    var after: GaugePair
    var currentKind: GaugeInputKind
    var current: GaugePair?
    var target: GaugePair?
}

enum GaugeCalculator {
    static func blockedSize(_ record: GaugeRecord) -> GaugePair? {
        guard let current = record.current, current.isPositive,
              record.before.isPositive, record.after.isPositive else { return nil }

        let result: GaugePair
        switch record.currentKind {
        case .size:
            result = GaugePair(across: current.across * (record.before.across / record.after.across),
                               down: current.down * (record.before.down / record.after.down))
        case .counts:
            guard current.across.rounded(.towardZero) == current.across,
                  current.down.rounded(.towardZero) == current.down else { return nil }
            result = GaugePair(across: current.across * (record.unit.swatchSpan / record.after.across),
                               down: current.down * (record.unit.swatchSpan / record.after.down))
        }
        return result.isPositive ? result : nil
    }

    static func targetCounts(_ record: GaugeRecord) -> (stitches: Int, rows: Int)? {
        guard let target = record.target, target.isPositive,
              record.before.isPositive, record.after.isPositive,
              let stitches = count(target.across, density: record.after.across, span: record.unit.swatchSpan),
              let rows = count(target.down, density: record.after.down, span: record.unit.swatchSpan) else { return nil }
        return (stitches, rows)
    }

    private static func count(_ length: Double, density: Double, span: Double) -> Int? {
        let value = length / span * density
        guard let rounded = Int(exactly: value.rounded()) else { return nil }
        return max(1, rounded)
    }
}
