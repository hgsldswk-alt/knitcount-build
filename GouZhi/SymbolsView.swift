import SwiftUI

private struct StitchSymbol: Identifiable {
    var id: Int
    var name: String
    var abbreviation: String
    var japanese: String
    static let all: [StitchSymbol] = [
        .init(id: 0, name: L.t("锁针"), abbreviation: "ch", japanese: "鎖編み"),
        .init(id: 1, name: L.t("引拔针"), abbreviation: "sl st", japanese: "引き抜き編み"),
        .init(id: 2, name: L.t("短针"), abbreviation: "sc", japanese: "細編み"),
        .init(id: 3, name: L.t("中长针"), abbreviation: "hdc", japanese: "中長編み"),
        .init(id: 4, name: L.t("长针"), abbreviation: "dc", japanese: "長編み"),
        .init(id: 5, name: L.t("长长针"), abbreviation: "tr", japanese: "長々編み"),
        .init(id: 6, name: L.t("短针 2 针并 1 针"), abbreviation: "sc2tog", japanese: "細編み2目一度"),
        .init(id: 7, name: L.t("短针 1 针放 2 针"), abbreviation: "inc", japanese: "細編み増し目"),
        .init(id: 8, name: L.t("长针减针"), abbreviation: "dc2tog", japanese: "長編み2目一度"),
        .init(id: 9, name: L.t("长针加针"), abbreviation: "dc inc", japanese: "長編み増し目"),
        .init(id: 10, name: L.t("环形起针"), abbreviation: "MR", japanese: "わの作り目"),
        .init(id: 11, name: L.t("外钩长针"), abbreviation: "FPdc", japanese: "表引き上げ編み"),
        .init(id: 12, name: L.t("内钩长针"), abbreviation: "BPdc", japanese: "裏引き上げ編み"),
        .init(id: 13, name: L.t("下针"), abbreviation: "k", japanese: "表目"),
        .init(id: 14, name: L.t("上针"), abbreviation: "p", japanese: "裏目"),
        .init(id: 15, name: L.t("空针"), abbreviation: "yo", japanese: "かけ目"),
        .init(id: 16, name: L.t("左上 2 并 1"), abbreviation: "ssk", japanese: "左上2目一度"),
        .init(id: 17, name: L.t("右上 2 并 1"), abbreviation: "k2tog", japanese: "右上2目一度")
    ]
}

struct SymbolsView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section { Text(L.t("缩写采用美式术语：美式 sc 对应英式 dc，美式 dc 对应英式 tr。")).font(.caption).foregroundStyle(Design.secondary) }
                ForEach(StitchSymbol.all) { symbol in
                    HStack(spacing: 20) {
                        SymbolPath(kind: symbol.id).stroke(Design.ink, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)).frame(width: 46, height: 48).padding(8).background(Design.background, in: RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 4) { Text(symbol.name).font(.headline); Text(symbol.abbreviation + " · " + symbol.japanese).font(.caption).foregroundStyle(Design.secondary) }
                    }.padding(.vertical, 4)
                }
            }.scrollContentBackground(.hidden).background(Design.background).navigationTitle(L.t("针法符号速查")).accessibilityIdentifier("symbolsList")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L.t("关闭")) { dismiss() }.accessibilityIdentifier("closeSheet") } }
        }
    }
}

struct SymbolPath: Shape {
    var kind: Int
    func path(in rect: CGRect) -> Path {
        var p = Path()
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height) }
        func line(_ x: CGFloat, _ y: CGFloat, _ xx: CGFloat, _ yy: CGFloat) { p.move(to: point(x, y)); p.addLine(to: point(xx, yy)) }
        func post(_ x: CGFloat, bars: Int = 1) {
            line(x, 0.85, x, 0.15); line(x - 0.15, 0.15, x + 0.15, 0.15)
            for i in 0..<bars { let y = 0.4 + CGFloat(i) * 0.14; line(x - 0.12, y + 0.07, x + 0.12, y - 0.07) }
        }
        switch kind {
        case 0: p.addEllipse(in: CGRect(x: rect.width * 0.18, y: rect.height * 0.35, width: rect.width * 0.64, height: rect.height * 0.3))
        case 1: p.addEllipse(in: CGRect(x: rect.width * 0.42, y: rect.height * 0.42, width: rect.width * 0.16, height: rect.height * 0.16)); line(0.43, 0.5, 0.57, 0.5)
        case 2: line(0.25, 0.25, 0.75, 0.75); line(0.75, 0.25, 0.25, 0.75)
        case 3: post(0.5, bars: 0)
        case 4: post(0.5)
        case 5: post(0.5, bars: 2)
        case 6, 8:
            line(0.2, 0.85, 0.5, 0.15); line(0.8, 0.85, 0.5, 0.15); line(0.35, 0.15, 0.65, 0.15)
            if kind == 8 { line(0.2, 0.5, 0.45, 0.6); line(0.55, 0.6, 0.8, 0.5) }
            else { line(0.2, 0.5, 0.5, 0.65); line(0.5, 0.65, 0.8, 0.5) }
        case 7, 9:
            line(0.5, 0.85, 0.2, 0.15); line(0.5, 0.85, 0.8, 0.15)
            if kind == 9 { line(0.1, 0.15, 0.35, 0.15); line(0.65, 0.15, 0.9, 0.15); line(0.22, 0.5, 0.44, 0.4); line(0.56, 0.4, 0.78, 0.5) }
            else { line(0.12, 0.5, 0.42, 0.35); line(0.58, 0.35, 0.88, 0.5) }
        case 10: p.addEllipse(in: rect.insetBy(dx: rect.width * 0.22, dy: rect.height * 0.22)); p.move(to: point(0.7, 0.8)); p.addQuadCurve(to: point(0.5, 0.2), control: point(0.35, 0.45))
        case 11, 12: post(0.5); p.move(to: point(0.25, 0.72)); p.addQuadCurve(to: point(0.75, 0.72), control: point(0.5, kind == 11 ? 1.0 : 0.42)); line(0.7, 0.63, 0.75, 0.72); line(0.66, 0.79, 0.75, 0.72)
        case 13: line(0.5, 0.2, 0.5, 0.8)
        case 14: line(0.2, 0.5, 0.8, 0.5)
        case 15: p.addEllipse(in: rect.insetBy(dx: rect.width * 0.22, dy: rect.height * 0.22))
        case 16: line(0.2, 0.2, 0.8, 0.8)
        default: line(0.8, 0.2, 0.2, 0.8)
        }
        return p
    }
}
