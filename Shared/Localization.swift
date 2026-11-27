import Foundation

enum L {
    static func t(_ key: String) -> String { NSLocalizedString(key, comment: "") }
    static func f(_ key: String, _ values: String...) -> String {
        String(format: t(key), locale: Locale.current, arguments: values)
    }
    static func duration(_ seconds: Int) -> String {
        String(format: "%d:%02d", max(0, seconds) / 3600, (max(0, seconds) / 60) % 60)
    }
}

extension CounterKind {
    var title: String {
        switch self { case .row: return L.t("行"); case .stitch: return L.t("针"); case .repeatCount: return L.t("重复"); case .custom: return L.t("自定义") }
    }
}
extension TrackerMode {
    var title: String {
        switch self { case .bar: return L.t("横条"); case .ring: return L.t("圆环"); case .grid: return L.t("网格"); case .none: return L.t("无") }
    }
}
extension ProjectStatus {
    var title: String {
        switch self { case .active: return L.t("进行中"); case .completed: return L.t("已完成"); case .planned: return L.t("想织") }
    }
}
