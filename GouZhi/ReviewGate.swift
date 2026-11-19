import Foundation

enum ReviewGate {
    static var completedShareClosed = false
    static var storeURL: URL? {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "APP_STORE_ID") as? String, !id.isEmpty else { return nil }
        return URL(string: "https://apps.apple.com/app/id" + id + "?action=write-review")
    }
    @MainActor static func shouldAsk(_ model: AppModel) -> Bool {
        guard completedShareClosed else { return false }; completedShareClosed = false
        guard !model.isolated, model.data.launchCount >= 5,
              Date().timeIntervalSince(model.data.entitlement.firstOpen) >= 3 * 86400 else { return false }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        guard model.data.reviewedVersion != version else { return false }
        model.mutate { $0.reviewedVersion = version }; return true
    }
}
