import SwiftUI
import UIKit

struct ColorworkEditor: View {
    @EnvironmentObject private var model: AppModel
    @State private var chart: ColorworkChart
    @State private var stroke: ColorworkChart?
    @State private var history = ChartEditHistory()
    @State private var viewport = ChartViewport()
    @State private var slot: UInt8
    @State private var lastCell: ChartCell?
    @State private var anchor: ChartCell?
    @State private var selection: ChartArea?
    @State private var selectionBeforeGesture: ChartArea?
    @State private var selecting = false
    @State private var placement: Placement?
    @State private var destination: ChartArea?
    @State private var errorText: String?
    @State private var panel: Panel?
    let projectID: UUID
    let goToLibrary: () -> Void

    private enum Placement { case copy, move }
    private enum Panel: String, Identifiable {
        case color, addColor, compare, gauge, tile, reading, share
        var id: String { rawValue }
    }

    init(chart: ColorworkChart, projectID: UUID, goToLibrary: @escaping () -> Void) {
        _chart = State(initialValue: chart)
        _slot = State(initialValue: UInt8(min(2, chart.palette.count)))
        self.projectID = projectID
        self.goToLibrary = goToLibrary
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(chart.name).font(.system(.title, design: .serif, weight: .semibold))
                        .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                    if let gauge = chart.gauge {
                        Text(L.f("针密 %@ × %@", CalculatorNumber.text(gauge.stitches), CalculatorNumber.text(gauge.rows)))
                            .font(.caption).foregroundStyle(Design.secondary)
                    }
                }
                colorways
                canvasCard
                palette
                editorActions
            }.padding(.horizontal, 16).padding(.vertical, 10)
        }
        .background(Design.background)
        .foregroundStyle(Design.ink)
        .navigationTitle(L.t("配色图解"))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(action: goToLibrary) {
                    Label(L.t("图解列表"), systemImage: "chevron.left")
                }.accessibilityIdentifier("colorworkLibrary")
            }
            ToolbarItem(placement: .primaryAction) {
                Button { panel = .share } label: { Image(systemName: "square.and.arrow.up") }
                    .accessibilityLabel(L.t("分享")).accessibilityIdentifier("shareColorwork")
            }
        }
        .sheet(item: $panel) { editorPanel($0) }
    }

    private var colorways: some View {
        HStack(spacing: 8) {
            ForEach(chart.colorways.indices, id: \.self) { index in
                Button {
                    var next = chart
                    next.activeColorway = index
                    commit(next)
                } label: {
                    Text(Self.label(index)).font(.subheadline.weight(.semibold))
                        .frame(minWidth: 44, minHeight: 44)
                        .foregroundStyle(index == chart.activeColorway ? .white : Design.ink)
                        .background(index == chart.activeColorway ? Design.accent : Design.card, in: Capsule())
                }.buttonStyle(.plain)
                    .accessibilityLabel(L.f("配色 %@", Self.label(index)))
                    .accessibilityAddTraits(index == chart.activeColorway ? .isSelected : [])
            }
            Spacer(minLength: 0)
            if chart.colorways.count < ColorworkChart.maxColorways {
                Button(L.t("复制配色"), systemImage: "plus") {
                    var next = chart
                    next.colorways.append(chart.palette)
                    next.activeColorway = next.colorways.count - 1
                    if commit(next) {
                        if slot == 0 { slot = 1 }
                        panel = .color
                    }
                }.font(.subheadline).tint(Design.accent)
            }
        }
    }

    private var canvasCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Text(L.f("%@ 针 × %@ 行", String(chart.width), String(chart.height))).font(.subheadline.monospacedDigit())
                Spacer(minLength: 4)
                Button(L.t("适配全图"), systemImage: "viewfinder") { viewport = ChartViewport() }
                    .font(.subheadline).frame(minHeight: 44)
            }.padding(.horizontal, 12)
            GeometryReader { geometry in
                ChartGrid(chart: stroke ?? chart, viewport: viewport, selection: selection, destination: destination)
                    .overlay {
                        ChartTouchInput(touch: { phase, point in
                            handle(phase, at: point, size: geometry.size)
                        }, zoom: { factor, point in
                            viewport.zoom(by: factor, at: point, size: geometry.size, chart: chart)
                        }, pan: { delta in
                            viewport.pan(delta, size: geometry.size, chart: chart)
                        }).accessibilityHidden(true)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(L.t("配色图解画布"))
                    .accessibilityValue(L.f("已涂 %@ 格", String(chart.cells.filter { $0 != 0 }.count)))
                    .accessibilityIdentifier("colorworkCanvas")
            }.frame(height: 270)
            HStack(spacing: 4) {
                Text(instruction).font(.caption).foregroundStyle(errorText == nil ? Design.secondary : Design.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("colorworkEditorHint")
                Button {
                    let start = !selecting
                    clearSelection()
                    selecting = start
                } label: {
                    Image(systemName: "rectangle.dashed").frame(width: 44, height: 44).contentShape(Rectangle())
                }.foregroundStyle(selecting ? Design.accent : Design.secondary)
                    .accessibilityLabel(L.t("矩形框选")).accessibilityAddTraits(selecting ? .isSelected : [])
                    .accessibilityIdentifier("selectChartRectangle")
                Button { travel(backward: true) } label: {
                    Image(systemName: "arrow.uturn.backward").frame(width: 44, height: 44).contentShape(Rectangle())
                }.disabled(history.undo.isEmpty).accessibilityLabel(L.t("撤销")).accessibilityIdentifier("undoColorwork")
                Button { travel(backward: false) } label: {
                    Image(systemName: "arrow.uturn.forward").frame(width: 44, height: 44).contentShape(Rectangle())
                }.disabled(history.redo.isEmpty).accessibilityLabel(L.t("重做")).accessibilityIdentifier("redoColorwork")
            }.padding(.leading, 12).padding(.trailing, 4)
            if selecting { selectionActions }
        }.background(Design.card, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Design.line).allowsHitTesting(false))
    }

    private var instruction: String {
        if let errorText { return errorText }
        if placement != nil { return L.t("点选目标左上角。整块放得下才会应用。") }
        return selecting ? L.t("拖动框选一块花纹。") : L.t("单指涂色，双指缩放或移动。")
    }

    private var selectionActions: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 16) {
                Button(L.t("复制到"), systemImage: "plus.square.on.square") { setPlacement(.copy) }
                    .disabled(selection == nil).accessibilityIdentifier("copyChartSelection")
                Button(L.t("移动到"), systemImage: "arrow.up.and.down.and.arrow.left.and.right") { setPlacement(.move) }
                    .disabled(selection == nil).accessibilityIdentifier("moveChartSelection")
                Button(L.t("水平镜像"), systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right") { mirror(horizontal: true) }
                    .disabled(selection == nil || placement != nil)
                Button(L.t("垂直镜像"), systemImage: "arrow.up.and.down.righttriangle.up.righttriangle.down") { mirror(horizontal: false) }
                    .disabled(selection == nil || placement != nil)
                Button(L.t("结束框选")) { clearSelection() }
            }.font(.subheadline).frame(minHeight: 44).padding(.horizontal, 12)
        }.scrollIndicators(.hidden)
    }

    private var palette: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(L.t("线色")).font(.headline)
                Spacer()
                Button(L.t("编辑线色")) {
                    if slot == 0 { slot = 1 }
                    panel = .color
                }.font(.subheadline).frame(minHeight: 44)
            }
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    swatch(0, color: nil)
                    ForEach(chart.palette.indices, id: \.self) { index in
                        swatch(UInt8(index + 1), color: chart.palette[index])
                    }
                    if chart.palette.count < ColorworkChart.maxColors {
                        Button { panel = .addColor } label: {
                            Image(systemName: "plus").frame(width: 44, height: 44)
                        }.accessibilityLabel(L.t("添加线色"))
                    }
                }
            }.scrollIndicators(.hidden)
        }.padding(.horizontal, 2)
    }

    private func swatch(_ index: UInt8, color: ChartSwatch?) -> some View {
        Button {
            slot = index
            clearSelection()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(color?.color ?? .white)
                if index == 0 {
                    Image(systemName: "eraser").foregroundStyle(Design.secondary)
                } else if slot == index {
                    Image(systemName: "checkmark.circle.fill").symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Design.ink)
                }
            }.frame(width: 34, height: 34).padding(5)
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(slot == index ? Design.accent : Design.line, lineWidth: 2))
                .frame(minWidth: 44, minHeight: 44)
        }.buttonStyle(.plain)
            .accessibilityLabel(color?.hex ?? L.t("擦除"))
            .accessibilityAddTraits(slot == index ? .isSelected : [])
            .accessibilityIdentifier("colorworkSwatch-" + String(index))
    }

    private var editorActions: some View {
        VStack(spacing: 8) {
            Button { model.followColorwork(chart) } label: {
                Label(L.t("开始跟织"), systemImage: "arrow.right").frame(maxWidth: .infinity, minHeight: 40)
            }.buttonStyle(.borderedProminent).tint(Design.accent).accessibilityIdentifier("followColorwork")
            HStack {
                Button(L.t("对比配色")) { panel = .compare }.frame(maxWidth: .infinity)
                Button(L.t("图解针密")) { panel = .gauge }.frame(maxWidth: .infinity)
                Menu {
                    Button(L.t("平铺花纹"), systemImage: "square.grid.2x2") { panel = .tile }
                    Button(L.t("跟织读法"), systemImage: "arrow.left.and.right") { panel = .reading }
                } label: {
                    Text(L.t("工具")).frame(maxWidth: .infinity, minHeight: 36)
                }.accessibilityIdentifier("colorworkTools")
            }.font(.subheadline).buttonStyle(.bordered)
        }
    }

    @ViewBuilder private func editorPanel(_ item: Panel) -> some View {
        switch item {
        case .color, .addColor:
            let adding = item == .addColor
            ColorworkColorPicker(color: adding || slot == 0 ? ColorworkChart.presets[1] : chart.palette[Int(slot) - 1],
                                 title: adding ? L.t("添加线色") : L.t("编辑线色")) { color in
                var next = chart
                if adding {
                    for i in next.colorways.indices { next.colorways[i].append(color) }
                } else {
                    next.colorways[next.activeColorway][Int(slot) - 1] = color
                }
                if next == chart || commit(next) {
                    if adding { slot = UInt8(next.palette.count) }
                    panel = nil
                }
            }
        case .compare:
            ColorworkCompare(chart: chart) { index in
                var next = chart
                next.activeColorway = index
                if next == chart || commit(next) { panel = nil }
            }
        case .gauge:
            ColorworkGauge(chart: chart) { gauge in
                var next = chart; next.gauge = gauge
                if next == chart || commit(next) { panel = nil; viewport = ChartViewport() }
            }
        case .tile:
            ColorworkTile(chart: chart) { next in
                if next == chart || commit(next) { panel = nil; clearSelection(); viewport = ChartViewport() }
            }
        case .reading:
            ColorworkReadingSettings(chart: chart) { next in
                next == chart || commit(next)
            }
        case .share:
            ColorworkShareSheet(chart: chart)
        }
    }

    private static func label(_ index: Int) -> String { ["A", "B", "C", "D"][index] }

    @discardableResult
    private func commit(_ value: ColorworkChart, record: Bool = true) -> Bool {
        guard value != chart, model.saveColorwork(value, replacing: chart, projectID: projectID) else { return false }
        if record { history.record(chart) }
        chart = value
        return true
    }

    private func travel(backward: Bool) {
        var next = history
        guard let target = next.step(from: chart, backward: backward), commit(target, record: false) else { return }
        history = next
        slot = min(slot, UInt8(chart.palette.count))
        viewport = ChartViewport()
        clearSelection()
    }

    private func clearSelection() {
        selecting = false
        selection = nil
        placement = nil
        destination = nil
        errorText = nil
    }

    private func setPlacement(_ mode: Placement) {
        placement = mode
        destination = nil
        errorText = nil
    }

    private func mirror(horizontal: Bool) {
        guard let selection else { return }
        var next = chart
        next.mirror(selection, horizontal: horizontal)
        commit(next)
    }

    private func handle(_ phase: ChartTouchPhase, at point: CGPoint, size: CGSize) {
        switch phase {
        case .began:
            guard let cell = viewport.cell(at: point, size: size, chart: chart, clamped: false) else { return }
            anchor = cell
            lastCell = cell
            errorText = nil
            selectionBeforeGesture = selection
            if let selection, placement != nil {
                destination = selection.at(cell)
            } else if selecting {
                selection = ChartArea(from: cell, to: cell)
            } else {
                var next = chart
                next.paint([cell], slot: slot)
                stroke = next
            }
        case .moved, .ended:
            guard let anchor, let cell = viewport.cell(at: point, size: size, chart: chart, clamped: true) else { return }
            if let selection, let placement {
                destination = selection.at(cell)
                if phase == .ended { place(selection, mode: placement, at: cell) }
            } else if selecting {
                selection = ChartArea(from: anchor, to: cell)
            } else if var next = stroke {
                next.paint((lastCell ?? cell).line(to: cell), slot: slot)
                stroke = next
                lastCell = cell
                if phase == .ended { commit(next) }
            }
            if phase == .ended { resetTouch() }
        case .cancelled:
            if anchor != nil { selection = selectionBeforeGesture; destination = nil }
            resetTouch()
        }
    }

    private func resetTouch() {
        anchor = nil
        lastCell = nil
        stroke = nil
        selectionBeforeGesture = nil
    }

    private func place(_ source: ChartArea, mode: Placement, at cell: ChartCell) {
        let target = source.at(cell)
        guard chart.fits(target) else { errorText = L.t("选区超出图解边缘，请换个位置。"); return }
        var next = chart
        switch mode {
        case .move: next.move(source, to: cell)
        case .copy: if let content = chart.sample(source) { next.paste(content, in: target) }
        }
        guard next == chart || commit(next) else { return }
        selection = target
        placement = nil
        destination = nil
    }
}
