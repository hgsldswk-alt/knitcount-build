import Foundation

enum ColorworkExchange {
    static let marker = "CW1:"
    static let fileExtension = "cwchart"
    static let maxFileBytes = 24_000
    private struct Payload: Codable { var version: Int; var chart: ColorworkChart }

    static func file(for chart: ColorworkChart) -> Data? {
        guard chart.valid else { return nil }
        return try? JSONEncoder().encode(Payload(version: 1, chart: chart))
    }

    static func read(_ file: Data) -> ColorworkChart? {
        guard file.count <= maxFileBytes, let payload = try? JSONDecoder().decode(Payload.self, from: file),
              payload.version == 1, payload.chart.valid else { return nil }
        var chart = payload.chart
        chart.id = UUID()
        return chart
    }

    static func code(for chart: ColorworkChart) -> String? {
        file(for: chart).map {
            marker + $0.base64EncodedString().replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        }
    }

    static func readCode(_ text: String) -> ColorworkChart? {
        guard text.utf8.count <= maxFileBytes * 2, let range = text.range(of: marker) else { return nil }
        let token = text[range.upperBound...].prefix { character in
            character.isASCII && (character.isLetter || character.isNumber || character == "-" || character == "_")
        }
        var base = token.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while !base.count.isMultiple(of: 4) { base += "=" }
        return Data(base64Encoded: base).flatMap(read)
    }
}
