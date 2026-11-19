import UIKit

enum DemoData {
    @MainActor static func make(store: Store, ring: Bool) -> AppData {
        let text = L.t("奶油色小熊玩偶\n第18–20圈：每圈36短针（36）\n第21圈：(5短针, 1减针) ×6（30）\n第22圈：每针1短针（30）\n放入安全眼，间隔6针\n第23圈：(4短针, 1减针) ×6（24）\n第24圈：(3短针, 1减针) ×6（18）\n开始塞棉花，边钩边塞\n第25圈：(2短针, 1减针) ×6（12）\n第26圈：6减针（6）\n第38圈：收针藏线（6）")
        let row = Counter(name: L.t("圈"), kind: .row, value: ring ? 8 : 23, min: 1)
        let stitch = Counter(name: L.t("本圈针数"), kind: .stitch, value: 14, min: 0, linkTo: row.id)
        let repeatCounter = Counter(name: L.t("花样"), kind: .repeatCount, value: 3, min: 1)
        var tracker = Tracker(mode: ring ? .ring : .bar, y: 0.38, step: 0.06, firstRadius: 0.06, ringSpacing: 0.025, radius: 0.235)
        tracker.dim = ring
        let image = diagram(ring: ring)
        var pages: [PatternPage] = []
        if let data = image.pngData(), let file = try? store.writeFile(data, extension: "png") {
            pages = [PatternPage(filename: file, aspectRatio: Double(image.size.width / image.size.height))]
        }
        var part = Part(counters: [row, stitch, repeatCounter], mainCounterID: stitch.id, patternPages: pages,
                        textPattern: ring ? nil : PatternParse.lines(text), tracker: tracker,
                        reminders: [RowReminder(atRow: 24, text: L.t("开始塞棉花，边钩边塞"), colorTag: 1)],
                        roundTargets: PatternParse.targets(PatternParse.lines(text)))
        if ring { for n in 1...30 { part.roundTargets[n] = n * 6 } }
        var bear = Project(name: L.t("奶油色小熊玩偶"), parts: [part], yarns: [Yarn(brand: L.t("棉线"), color: L.t("奶油色"), amount: "40 g")], hookSize: "2.5 mm", totalSeconds: 13_320)
        bear.coverFilename = pages.first?.filename
        let cardiganText = L.t("燕麦色开衫\nRow 45: K36 (40, 44, 48), P2 (2, 4, 4) (80 sts)\nRow 46: K36 (40, 44, 48), P2 (2, 4, 4) (80 sts)\nRow 47: K36 (40, 44, 48), P2 (2, 4, 4) (80 sts)\nRow 120: Bind off (80 sts)")
        let back = Part(name: L.t("后片"), counters: [Counter(name: L.t("行"), value: 46)], textPattern: PatternParse.lines(cardiganText), roundTargets: PatternParse.targets(PatternParse.lines(cardiganText)), sizeIndex: 1)
        var cardigan = Project(name: L.t("燕麦色开衫"), parts: [back, Part(name: L.t("袖子"), copies: 2)], hookSize: "4 mm", size: "M", totalSeconds: 57_600, lastOpened: Date().addingTimeInterval(-3 * 86400))
        let day = DateFormatter(); day.locale = Locale(identifier: "en_US_POSIX"); day.dateFormat = "yyyy-MM-dd"
        bear.weeklySeconds[day.string(from: Date())] = 7200; cardigan.weeklySeconds[day.string(from: Date())] = 8400
        let ornamentPages = (0..<4).map { _ in PatternPage(filename: pages.first?.filename ?? "", aspectRatio: pages.first?.aspectRatio ?? 0.75) }
        let ornament = Project(name: L.t("圣诞挂件 ×6"), status: .planned, parts: [Part(patternPages: ornamentPages)])
        var state = AppData(projects: [bear, cardigan, ornament], recentID: bear.id)
        state.milestones = Set(["first", "half-" + bear.id.uuidString, "half-" + cardigan.id.uuidString])
        return state
    }
    static func diagram(ring: Bool) -> UIImage {
        let size = CGSize(width: 780, height: ring ? 780 : 1040)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            let context = renderer.cgContext
            UIColor(red: 1, green: 0.992, blue: 0.98, alpha: 1).setFill(); context.fill(CGRect(origin: .zero, size: size))
            UIColor(red: 0.23, green: 0.21, blue: 0.18, alpha: 1).setStroke(); context.setLineWidth(2)
            if ring {
                for round in 1...12 {
                    let radius = CGFloat(round) * 27
                    context.strokeEllipse(in: CGRect(x: 390 - radius, y: 390 - radius, width: radius * 2, height: radius * 2))
                    for stitch in 0..<(round * 6) {
                        let angle = CGFloat(stitch) / CGFloat(round * 6) * .pi * 2
                        let x = 390 + cos(angle) * radius, y = 390 + sin(angle) * radius
                        context.move(to: CGPoint(x: x - 4, y: y - 4)); context.addLine(to: CGPoint(x: x + 4, y: y + 4))
                        context.move(to: CGPoint(x: x + 4, y: y - 4)); context.addLine(to: CGPoint(x: x - 4, y: y + 4)); context.strokePath()
                    }
                }
            } else {
                let title = L.t("我的图解") as NSString
                title.draw(at: CGPoint(x: 45, y: 35), withAttributes: [.font: UIFont.systemFont(ofSize: 30, weight: .semibold), .foregroundColor: UIColor.darkGray])
                for y in stride(from: 120, through: 920, by: 40) { context.move(to: CGPoint(x: 70, y: CGFloat(y))); context.addLine(to: CGPoint(x: 710, y: CGFloat(y))); context.strokePath() }
                for x in stride(from: 70, through: 710, by: 40) { context.move(to: CGPoint(x: CGFloat(x), y: 120)); context.addLine(to: CGPoint(x: CGFloat(x), y: 920)); context.strokePath() }
                for row in 0..<20 { for col in 0..<16 where (row + col) % 3 == 0 {
                    let x = CGFloat(90 + col * 40), y = CGFloat(140 + row * 40)
                    context.move(to: CGPoint(x: x - 9, y: y - 10)); context.addLine(to: CGPoint(x: x, y: y + 10)); context.addLine(to: CGPoint(x: x + 9, y: y - 10)); context.strokePath()
                } }
            }
        }
    }
}
