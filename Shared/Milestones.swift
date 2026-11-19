import Foundation

enum Milestones {
    static func fresh(projects: [Project], announced: inout Set<String>) -> [String] {
        var earned: [String] = []
        let completed = projects.filter { $0.status == .completed }.count
        if completed >= 1 { earned.append("first") }
        if completed >= 10 { earned.append("ten") }
        if projects.reduce(0, { $0 + $1.totalSeconds }) >= 360_000 { earned.append("hours") }
        for p in projects {
            if p.totalRows >= 1000 { earned.append("rows-" + p.id.uuidString) }
            if p.progress >= 0.5 { earned.append("half-" + p.id.uuidString) }
        }
        let fresh = earned.filter { !announced.contains($0) }
        announced.formUnion(fresh); return fresh
    }
    static func title(_ key: String) -> String {
        if key == "first" { return L.t("第一件作品完成了") }
        if key == "ten" { return L.t("完成了 10 件作品") }
        if key == "hours" { return L.t("与毛线相伴 100 小时") }
        if key.hasPrefix("rows-") { return L.t("一针一线，1000 行") }
        return L.t("织到一半了")
    }
}
