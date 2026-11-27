import Foundation

enum Launch {
    static let freePeriod = false
    static var isFree: Bool { isFree(arguments: ProcessInfo.processInfo.arguments) }
    static func isFree(arguments: [String]) -> Bool {
        freePeriod && !arguments.contains(where: { ["-paid-mode", "-paywall", "-expired"].contains($0) })
    }
}

extension Entitlement {
    func hasPro(at now: Date, arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        Launch.isFree(arguments: arguments) || isPremium(at: now)
    }
}
