import Foundation

enum CountEvent: Equatable {
    case rowCompleted(Int)
    case reminderHit(RowReminder)
    case patternRepeatDone(UUID)
}
struct CountResult {
    var part: Part
    var events: [CountEvent]
}
enum Counting {
    static let limit = 1_000_000_000
    static func target(for counter: Counter, in part: Part) -> Int? {
        if counter.kind == .stitch, let n = part.roundTargets[part.row], n > 0 { return n }
        return counter.resetAt.flatMap { $0 > 0 ? $0 : nil }
    }
    static func upperBound(for counter: Counter, in part: Part) -> Int? {
        target(for: counter, in: part).map { max(counter.min, counter.min == 0 ? $0 - 1 : $0) }
    }
    static func increment(_ part: Part, counterID: UUID, linked: Bool = true) -> CountResult {
        change(part, counterID: counterID, delta: 1, linked: linked)
    }
    static func decrement(_ part: Part, counterID: UUID, linked: Bool = true) -> CountResult {
        change(part, counterID: counterID, delta: -1, linked: linked)
    }
    private static func change(_ original: Part, counterID: UUID, delta: Int, linked: Bool) -> CountResult {
        var part = original
        var events: [CountEvent] = []
        var visited = Set<UUID>()
        func link(_ c: Counter) -> UUID? {
            let row = c.kind == .stitch && !part.roundTargets.isEmpty ? part.counters.first(where: { $0.kind == .row })?.id : nil
            return c.linkTo ?? row
        }
        func canBorrow(_ id: UUID, seen: Set<UUID>) -> Bool {
            guard !seen.contains(id), let c = part.counters.first(where: { $0.id == id }) else { return false }
            if c.value > c.min { return true }
            guard let next = link(c), upperBound(for: c, in: part) != nil else { return false }
            return canBorrow(next, seen: seen.union([id]))
        }
        func move(_ id: UUID, _ amount: Int) {
            guard visited.insert(id).inserted, let i = part.counters.firstIndex(where: { $0.id == id }) else { return }
            let c = part.counters[i]
            let next = link(c)
            if amount > 0 {
                guard c.value < limit else { return }
                if linked, let upper = upperBound(for: c, in: part), c.value >= upper {
                    part.counters[i].value = c.min
                    events.append(.patternRepeatDone(id))
                    if let next, !visited.contains(next) { move(next, 1) }
                } else { part.counters[i].value = max(c.min, c.value + 1) }
            } else if c.value > c.min {
                part.counters[i].value -= 1
            } else if linked, let next, canBorrow(next, seen: visited), upperBound(for: c, in: part) != nil {
                move(next, -1)
                if let upper = upperBound(for: c, in: part) { part.counters[i].value = upper }
            }
        }
        move(counterID, delta)
        if original.row != part.row {
            part.rowsWorked = max(0, max(original.rowsWorked, original.row - 1) + delta)
            if linked || part.tracker.mode == .bar || part.tracker.mode == .none { moveTracker(&part, from: original.row) }
            if delta > 0 {
                events.append(.rowCompleted(original.row))
                events += part.reminders.filter { $0.atRow == part.row }.map { .reminderHit($0) }
            }
        }
        if linked && part.tracker.mode == .grid {
            let stitch = part.counters.first(where: { $0.kind == .stitch })?.value ?? 0
            let backwards = part.tracker.alternating && part.row % 2 == 0
            let columns = max(1, Int((1 - part.tracker.originX) / max(0.005, part.tracker.cellWidth)))
            part.tracker.gridColumn = backwards ? max(0, columns - 1 - stitch) : stitch
        }
        return CountResult(part: part, events: events)
    }
    static func moveTracker(_ part: inout Part, from previous: Int) {
        let row = part.row
        if part.tracker.mode == .bar {
            for (page, pattern) in part.patternPages.enumerated() {
                let index = pattern.rowMap[row] ?? (pattern.rowMap.isEmpty ? row - 1 : -1)
                if let lines = pattern.ocrLines, lines.indices.contains(index) {
                    part.tracker.page = page
                    part.tracker.y = Double(lines[index].minY)
                    part.tracker.height = max(0.01, Double(lines[index].height))
                    part.tracker.pageY[page] = part.tracker.y
                    return
                }
            }
            var y = part.tracker.y + Double(row - previous) * part.tracker.step
            if y + part.tracker.height > 1, part.tracker.page + 1 < part.patternPages.count { part.tracker.page += 1; y = 0.02 }
            if y < 0, part.tracker.page > 0 { part.tracker.page -= 1; y = 0.9 }
            part.tracker.y = min(max(0, 1 - part.tracker.height), max(0, y))
            part.tracker.pageY[part.tracker.page] = part.tracker.y
        } else if part.tracker.mode == .ring {
            part.tracker.radius = min(0.7, max(0.005, part.tracker.firstRadius + Double(max(0, row - 1)) * part.tracker.ringSpacing))
        } else if part.tracker.mode == .grid {
            part.tracker.y = min(0.98, max(0, part.tracker.originY + Double(max(0, row - 1)) * part.tracker.cellHeight))
        }
    }
    static func remember(_ part: Part, in stack: inout [UndoStep], at date: Date = Date()) {
        stack.append(UndoStep(counters: part.counters, tracker: part.tracker, at: date, rowsWorked: part.rowsWorked))
        if stack.count > 50 { stack.removeFirst(stack.count - 50) }
    }
    static func undo(_ part: Part, stack: inout [UndoStep]) -> Part {
        guard let step = stack.popLast() else { return part }
        var result = part; result.counters = step.counters; result.tracker = step.tracker; result.rowsWorked = step.rowsWorked
        return result
    }
}

extension Part {
    var row: Int { counters.first(where: { $0.kind == .row })?.value ?? 1 }
    var selectedCounter: Counter? { counters.first(where: { $0.id == mainCounterID }) ?? counters.first }
    var historyKey: String { id.uuidString }
}
extension Project {
    var part: Part { parts.first(where: { $0.id == selectedPartID }) ?? parts.first ?? Part() }
    var totalRows: Int { parts.reduce(0) { $0 + max($1.rowsWorked, max(0, $1.row - 1)) } }
    var targetRows: Int { part.roundTargets.keys.max() ?? part.textPattern?.compactMap(\.row).max() ?? 0 }
    var progress: Double { targetRows > 0 ? min(1, Double(part.row) / Double(targetRows)) : 0 }
}
