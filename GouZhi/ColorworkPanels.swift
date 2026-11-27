import SwiftUI
import UIKit

private struct ColorworkPanel<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        NavigationStack {
            content.navigationTitle(title).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L.t("关闭")) { dismiss() } } }
        }
    }
}

struct ColorworkColorPicker: View {
    @State private var custom: Color
    let title: String
    let apply: (ChartSwatch) -> Void

    init(color: ChartSwatch, title: String, apply: @escaping (ChartSwatch) -> Void) {
        _custom = State(initialValue: color.color)
        self.title = title
        self.apply = apply
    }

    var body: some View {
        ColorworkPanel(title: title) {
            ScrollView {
                VStack(spacing: 16) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 56))], spacing: 10) {
                        ForEach(ColorworkChart.presets, id: \.self) { color in
                            Button { apply(color) } label: {
                                RoundedRectangle(cornerRadius: 12).fill(color.color)
                                    .frame(height: 48).overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Design.line))
                            }.accessibilityLabel(color.hex)
                        }
                    }
                    ColorPicker(L.t("自定义颜色"), selection: $custom, supportsOpacity: false)
                    Button(L.t("应用颜色")) {
                        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
                        guard UIColor(custom).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return }
                        apply(ChartSwatch(byte(red), byte(green), byte(blue)))
                    }.buttonStyle(.borderedProminent)
                }.padding(20)
            }.background(Design.background)
        }
    }

    private func byte(_ value: CGFloat) -> UInt8 { UInt8((255 * max(0, min(1, value))).rounded()) }
}

struct ColorworkCompare: View {
    let chart: ColorworkChart
    let select: (Int) -> Void

    var body: some View {
        ColorworkPanel(title: L.t("对比配色")) {
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(chart.colorways.indices, id: \.self) { index in
                        compareCard(index)
                    }
                }.padding(16)
            }.background(Design.background)
        }
    }

    private func compareCard(_ index: Int) -> some View {
        var variant = chart
        variant.activeColorway = index
        return Button { select(index) } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(L.f("配色 %@", ["A", "B", "C", "D"][index])).font(.subheadline.bold())
                    Spacer()
                    if index == chart.activeColorway { Image(systemName: "checkmark").foregroundStyle(Design.accent) }
                }
                ChartGrid(chart: variant, axes: false).frame(height: 118).accessibilityHidden(true)
                HStack(spacing: 4) {
                    ForEach(variant.palette.indices, id: \.self) { i in
                        Circle().fill(variant.palette[i].color).frame(width: 10, height: 10)
                    }
                }.accessibilityHidden(true)
            }.knitCard()
        }.buttonStyle(.plain).accessibilityAddTraits(index == chart.activeColorway ? .isSelected : [])
    }
}

struct ColorworkGauge: View {
    @State private var stitches: String
    @State private var rows: String
    @FocusState private var focus: String?
    let chart: ColorworkChart
    let apply: (ColorworkChart.Gauge?) -> Void

    init(chart: ColorworkChart, apply: @escaping (ColorworkChart.Gauge?) -> Void) {
        self.chart = chart
        self.apply = apply
        _stitches = State(initialValue: chart.gauge.map { CalculatorNumber.text($0.stitches) } ?? "")
        _rows = State(initialValue: chart.gauge.map { CalculatorNumber.text($0.rows) } ?? "")
    }

    private var gauge: ColorworkChart.Gauge? {
        guard let width = CalculatorNumber.decimal(stitches), let height = CalculatorNumber.decimal(rows) else { return nil }
        let result = ColorworkChart.Gauge(stitches: NSDecimalNumber(decimal: width).doubleValue,
                                          rows: NSDecimalNumber(decimal: height).doubleValue)
        return result.valid ? result : nil
    }

    var body: some View {
        CalculatorSheet(title: L.t("图解针密"), finishInput: { focus = nil }) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    CalculatorField(title: L.t("每 10 cm 针数"), id: "chartGaugeStitches", value: $stitches, focus: $focus, placeholder: "22")
                    CalculatorField(title: L.t("每 10 cm 行数"), id: "chartGaugeRows", value: $rows, focus: $focus, placeholder: "28")
                }
                ChartGrid(chart: preview).frame(height: 155).background(Design.card, in: RoundedRectangle(cornerRadius: 12))
                Button(L.t("应用针密")) { if let gauge { apply(gauge) } }.buttonStyle(.borderedProminent).disabled(gauge == nil)
                if chart.gauge != nil { Button(L.t("清除针密")) { apply(nil) } }
                if !stitches.isEmpty, !rows.isEmpty, gauge == nil {
                    Text(L.t("每 10 cm 的针数和行数须在 0.5–200 之间。")).font(.footnote).foregroundStyle(Design.accent)
                }
            }
        }
    }

    private var preview: ColorworkChart {
        var preview = chart
        preview.gauge = gauge ?? chart.gauge
        return preview
    }
}

struct ColorworkTile: View {
    @State private var across = 1
    @State private var down = 1
    let chart: ColorworkChart
    let apply: (ColorworkChart) -> Void

    var body: some View {
        ColorworkPanel(title: L.t("平铺花纹")) {
            Form {
                Stepper(L.f("横向 %@ 组", String(across)), value: $across, in: 1...(ColorworkChart.maxSide / chart.width))
                Stepper(L.f("纵向 %@ 组", String(down)), value: $down, in: 1...(ColorworkChart.maxSide / chart.height))
                ChartGrid(chart: preview).frame(height: 220)
                Button(L.t("应用平铺")) { apply(preview) }.disabled(across == 1 && down == 1)
            }
        }
    }

    private var preview: ColorworkChart {
        var preview = chart
        preview.tile(across: across, down: down)
        return preview
    }
}

struct ColorworkReadingSettings: View {
    @State private var chart: ColorworkChart
    let apply: (ColorworkChart) -> Bool

    init(chart: ColorworkChart, apply: @escaping (ColorworkChart) -> Bool) {
        _chart = State(initialValue: chart)
        self.apply = apply
    }

    var body: some View {
        ColorworkPanel(title: L.t("跟织读法")) {
            Form {
                Picker(L.t("跟织读法"), selection: $chart.reading) {
                    Text(L.t("平织往返")).tag(ChartReading.flat)
                    Text(L.t("圈织")).tag(ChartReading.round)
                }.pickerStyle(.segmented)
                Toggle(L.t("第 1 行从右侧起针"), isOn: $chart.firstAtRight)
            }
        }
        .onChange(of: chart) { old, new in
            if !apply(new) { chart = old }
        }
    }
}

struct ColorworkShareSheet: View {
    @State private var shared: [Any] = []
    @State private var showingShare = false
    @State private var status: String?
    let chart: ColorworkChart
    private let topics = "#colorwork #fairisle"

    var body: some View {
        ColorworkPanel(title: L.t("分享图解")) {
            ScrollView {
                ViewThatFits(in: .horizontal) {
                    shareCard
                    cardContent.frame(maxWidth: .infinity).background(Design.card)
                }
                VStack(spacing: 10) {
                    Button(L.t("分享图解图片"), systemImage: "square.and.arrow.up") { exportImage() }
                        .buttonStyle(.borderedProminent).accessibilityIdentifier("exportColorworkImage")
                    Button(L.t("复制图解口令"), systemImage: "doc.on.doc") {
                        if let code = ColorworkExchange.code(for: chart) {
                            UIPasteboard.general.string = code
                            status = L.t("已复制图解口令")
                        }
                    }
                    Button(L.t("导出图解文件"), systemImage: "doc") {
                        if let data = ColorworkExchange.file(for: chart) { export(data, extension: ColorworkExchange.fileExtension) }
                    }
                    if let status { Text(status).font(.footnote).foregroundStyle(Design.secondary) }
                }.padding(.vertical, 16)
            }.background(Design.background)
        }.sheet(isPresented: $showingShare) { SystemShare(items: shared) }
    }

    private var shareCard: some View { cardContent.frame(width: 360, height: 450).background(Design.card) }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(chart.name).font(.system(size: 27, weight: .semibold, design: .serif)).lineLimit(1).minimumScaleFactor(0.55)
            Text(L.f("%@ 针 × %@ 行", String(chart.width), String(chart.height))).font(.subheadline).foregroundStyle(Design.secondary)
            ChartGrid(chart: chart).frame(height: 256).background(Design.background, in: RoundedRectangle(cornerRadius: 10))
            HStack(spacing: 5) {
                ForEach(chart.palette.indices, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 4).fill(chart.palette[i].color).frame(width: 25, height: 12)
                }
            }
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L.t("钩织计数")).font(.subheadline.bold())
                    Text(topics).font(.caption).foregroundStyle(Design.accent)
                }
                Spacer()
                if let qr = StoreShareQR.image() {
                    Image(uiImage: qr).interpolation(.none).resizable().frame(width: 52, height: 52)
                        .padding(5).background(.white).accessibilityLabel(L.t("下载二维码"))
                }
            }
        }.padding(18).foregroundStyle(Design.ink)
    }

    @MainActor private func exportImage() {
        let renderer = ImageRenderer(content: shareCard)
        renderer.scale = 3
        guard let bytes = renderer.uiImage?.pngData() else { status = L.t("导出失败，请稍后重试。"); return }
        export(bytes, extension: "png")
    }

    private func export(_ data: Data, extension suffix: String) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(suffix)
        do {
            try data.write(to: url, options: .atomic)
            shared = suffix == "png" ? [url, topics] : [url]
            showingShare = true
        } catch {
            status = L.t("导出失败，请稍后重试。")
        }
    }
}
