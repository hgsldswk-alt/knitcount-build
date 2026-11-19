import Foundation
import Compression

enum ShareCode {
    static let marker = "#钩织计数#"
    static let maxTextLength = 6000
    static let maxJSONLength = 1_048_576
    struct Encoded { var text: String; var omittedText: Bool }
    private struct Payload: Codable { var v: Int; var project: Project }
    static func encode(_ project: Project) -> Encoded? {
        var clean = portable(project)
        for attempt in 0...1 {
            if valid(clean), let json = try? JSONEncoder().encode(Payload(v: 1, project: clean)), let packed = pack(json) {
                let base = packed.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
                let text = marker + base + "#"
                if text.count <= maxTextLength { return Encoded(text: text, omittedText: attempt == 1) }
            }
            for i in clean.parts.indices { clean.parts[i].textPattern = nil }
        }
        return nil
    }
    static func portable(_ project: Project) -> Project {
        var p = project
        p.coverFilename = nil; p.photos = []; p.totalSeconds = 0; p.weeklySeconds = [:]
        p.status = .active; p.completedAt = nil
        for i in p.parts.indices { p.parts[i].patternPages = []; p.parts[i].tracker = Tracker(); p.parts[i].rowsWorked = 0 }
        return p
    }
    static func decode(_ text: String) -> Project? {
        guard text.utf8.count <= 100_000 else { return nil }
        let normalized = text.replacingOccurrences(of: "＃", with: "#")
        guard let start = normalized.range(of: marker) else { return nil }
        let rest = normalized[start.upperBound...]
        guard let end = rest.firstIndex(of: "#") else { return nil }
        let raw = rest[..<end].filter { !$0.isWhitespace }
        guard !raw.isEmpty, raw.count <= maxTextLength, raw.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 }), raw.count % 4 != 1 else { return nil }
        var base = raw.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base.count % 4 != 0 { base += "=" }
        guard let packed = Data(base64Encoded: base), let json = unpack(packed),
              let payload = try? JSONDecoder().decode(Payload.self, from: json), payload.v == 1, valid(payload.project) else { return nil }
        var p = portable(payload.project)
        p.id = UUID(); p.createdAt = Date(); p.lastOpened = Date()
        for i in p.parts.indices {
            let ids = Dictionary(uniqueKeysWithValues: p.parts[i].counters.map { ($0.id, UUID()) })
            p.parts[i].id = UUID()
            p.parts[i].currentCopy = 1
            p.parts[i].mainCounterID = p.parts[i].mainCounterID.flatMap { ids[$0] }
            for j in p.parts[i].counters.indices {
                let old = p.parts[i].counters[j]
                p.parts[i].counters[j].id = ids[old.id]!
                p.parts[i].counters[j].linkTo = old.linkTo.flatMap { ids[$0] }
                p.parts[i].counters[j].value = old.min
            }
        }
        p.selectedPartID = p.parts.first?.id
        return p
    }
    static func valid(_ p: Project) -> Bool {
        guard p.name.count <= 500, (1...100).contains(p.parts.count), p.yarns.count <= 100,
              Set(p.parts.map(\.id)).count == p.parts.count else { return false }
        for part in p.parts {
            guard (1...100).contains(part.counters.count), (1...1000).contains(part.copies),
                  Set(part.counters.map(\.id)).count == part.counters.count,
                  part.roundTargets.allSatisfy({ (1...100_000).contains($0.key) && (1...Counting.limit).contains($0.value) }),
                  (part.textPattern?.count ?? 0) <= 20_000 else { return false }
            let ids = Set(part.counters.map(\.id))
            for c in part.counters {
                guard (0...Counting.limit).contains(c.min), (c.min...Counting.limit).contains(c.value),
                      c.resetAt == nil || (1...Counting.limit).contains(c.resetAt!),
                      c.linkTo == nil || ids.contains(c.linkTo!) else { return false }
                var seen = Set<UUID>(); var next: UUID? = c.id
                while let id = next {
                    guard seen.insert(id).inserted else { return false }
                    if let counter = part.counters.first(where: { $0.id == id }) {
                        next = counter.linkTo ?? (counter.kind == .stitch && !part.roundTargets.isEmpty ? part.counters.first(where: { $0.kind == .row })?.id : nil)
                    } else { next = nil }
                }
            }
        }
        return true
    }
    private static func adler(_ bytes: [UInt8]) -> UInt32 {
        var a: UInt32 = 1, b: UInt32 = 0
        for v in bytes { a = (a + UInt32(v)) % 65521; b = (b + a) % 65521 }
        return (b << 16) | a
    }
    static func pack(_ data: Data) -> Data? {
        guard !data.isEmpty, data.count <= maxJSONLength else { return nil }
        let source = [UInt8](data)
        var destination = [UInt8](repeating: 0, count: maxJSONLength + 65_536)
        let capacity = destination.count
        let count = source.withUnsafeBufferPointer { src in
            destination.withUnsafeMutableBufferPointer { dst in
                compression_encode_buffer(dst.baseAddress!, capacity, src.baseAddress!, source.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard count > 0 else { return nil }
        let check = adler(source)
        return Data([0x78, 0x9c] + Array(destination.prefix(count)) + [UInt8((check >> 24) & 255), UInt8((check >> 16) & 255), UInt8((check >> 8) & 255), UInt8(check & 255)])
    }
    static func unpack(_ data: Data) -> Data? {
        let bytes = [UInt8](data)
        guard bytes.count >= 7, bytes.count <= maxTextLength, bytes[0] & 15 == 8,
              bytes[0] >> 4 <= 7, (Int(bytes[0]) * 256 + Int(bytes[1])) % 31 == 0, bytes[1] & 32 == 0 else { return nil }
        let source = Array(bytes[2..<(bytes.count - 4)])
        var destination = [UInt8](repeating: 0, count: maxJSONLength + 1)
        let capacity = destination.count
        let count = source.withUnsafeBufferPointer { src in
            destination.withUnsafeMutableBufferPointer { dst in
                compression_decode_buffer(dst.baseAddress!, capacity, src.baseAddress!, source.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard count > 0, count <= maxJSONLength else { return nil }
        let json = Array(destination.prefix(count))
        let check = bytes.suffix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard adler(json) == check else { return nil }; return Data(json)
    }
}
