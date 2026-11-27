import SwiftUI

struct ColorworkFollowView: View {
    @EnvironmentObject private var model: AppModel
    @State private var viewport = ChartViewport()
    var chart: ColorworkChart
    var row: Int

    private var direction: String {
        chart.reading.startsAtRight(row: row, firstAtRight: chart.firstAtRight) ? L.t("从右向左") : L.t("从左向右")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Label(chart.name, systemImage: "square.grid.3x3")
                    .font(.caption.weight(.medium)).lineLimit(1)
                Spacer()
                Button {
                    model.sheet = .colorwork(chart.id)
                } label: {
                    Image(systemName: "pencil").frame(width: 36, height: 36)
                }.accessibilityLabel(L.t("编辑配色图解")).accessibilityIdentifier("editFollowingColorwork")
                Menu {
                    Button(L.t("适配全图")) { viewport = ChartViewport() }
                    Button(L.t("返回原图解")) { model.editPart { $0.activeColorworkID = nil } }
                } label: {
                    Image(systemName: "ellipsis").frame(width: 36, height: 36)
                }.accessibilityLabel(L.t("图解选项"))
            }.padding(.horizontal, 10)
            GeometryReader { geometry in
                ChartGrid(chart: chart, viewport: viewport, row: row)
                    .overlay {
                        ChartTouchInput(touch: { _, _ in }, zoom: { factor, point in
                            viewport.zoom(by: factor, at: point, size: geometry.size, chart: chart)
                        }, pan: { delta in
                            viewport.pan(delta, size: geometry.size, chart: chart)
                        }).accessibilityHidden(true)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(L.t("配色图解"))
                    .accessibilityIdentifier("followingColorworkGrid")
            }
            HStack(spacing: 5) {
                if chart.gridRow(for: row) != nil {
                    Image(systemName: chart.reading.startsAtRight(row: row, firstAtRight: chart.firstAtRight)
                          ? "arrow.left" : "arrow.right").accessibilityHidden(true)
                    Text(L.f("第 %@ / %@ 行", String(row), String(chart.height)))
                        .accessibilityIdentifier("colorworkActiveRow")
                    Text(direction).accessibilityIdentifier("colorworkReadingDirection")
                } else {
                    Text(row < 1 ? L.t("图解从第 1 行开始") : L.t("已织完这张图解"))
                        .accessibilityIdentifier("colorworkActiveRow")
                }
            }.font(.caption.weight(.semibold)).foregroundStyle(Design.accent).padding(.bottom, 6)
        }.foregroundStyle(Design.ink).background(Design.card)
    }
}
