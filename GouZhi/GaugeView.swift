import SwiftUI

struct GaugeSheet: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        GaugeForm(projectID: model.project?.id, saved: model.project?.gauge)
            .id(model.project?.id)
    }
}

private struct GaugeValues {
    var across = ""
    var down = ""

    init(_ pair: GaugePair? = nil) {
        if let pair {
            across = CalculatorNumber.text(pair.across, digits: 12)
            down = CalculatorNumber.text(pair.down, digits: 12)
        }
    }

    var pair: GaugePair? {
        guard let across = Self.number(across), let down = Self.number(down) else { return nil }
        let pair = GaugePair(across: across, down: down)
        return pair.isPositive ? pair : nil
    }

    private static func number(_ input: String) -> Double? {
        CalculatorNumber.decimal(input).map { NSDecimalNumber(decimal: $0).doubleValue }
    }

    mutating func convert(_ transform: (Double) -> Double) {
        if let number = Self.number(across) { across = CalculatorNumber.text(transform(number), digits: 12) }
        if let number = Self.number(down) { down = CalculatorNumber.text(transform(number), digits: 12) }
    }
}

private struct GaugeForm: View {
    @EnvironmentObject private var model: AppModel
    @FocusState private var focused: String?
    @State private var unit: GaugeUnit
    @State private var currentKind: GaugeInputKind
    @State private var before: GaugeValues
    @State private var after: GaugeValues
    @State private var size: GaugeValues
    @State private var counts: GaugeValues
    @State private var target: GaugeValues
    @State private var saved: GaugeRecord?
    @State private var showSavedResultFirst: Bool
    @State private var showingPaywall = false
    private let projectID: UUID?

    init(projectID: UUID?, saved: GaugeRecord?) {
        self.projectID = projectID
        _showSavedResultFirst = State(initialValue: saved != nil)
        _unit = State(initialValue: saved?.unit ?? .centimetres)
        _currentKind = State(initialValue: saved?.currentKind ?? .size)
        _before = State(initialValue: GaugeValues(saved?.before))
        _after = State(initialValue: GaugeValues(saved?.after))
        _size = State(initialValue: GaugeValues(saved?.currentKind == .size ? saved?.current : nil))
        _counts = State(initialValue: GaugeValues(saved?.currentKind == .counts ? saved?.current : nil))
        _target = State(initialValue: GaugeValues(saved?.target))
        _saved = State(initialValue: saved)
    }

    private var record: GaugeRecord? {
        guard let before = before.pair, let after = after.pair else { return nil }
        return GaugeRecord(unit: unit, before: before, after: after, currentKind: currentKind,
                           current: currentKind == .size ? size.pair : counts.pair, target: target.pair)
    }

    private var unitLabel: String { unit == .centimetres ? "cm" : "in" }

    var body: some View {
        CalculatorSheet(title: L.t("小样换算"), finishInput: { focused = nil }) {
            VStack(alignment: .leading, spacing: 14) {
                if showSavedResultFirst { resultSection }
                Picker(L.t("尺寸单位"), selection: Binding(get: { unit }, set: switchUnit)) {
                    Text("10 cm").tag(GaugeUnit.centimetres)
                    Text(L.t("4 英寸")).tag(GaugeUnit.inches)
                }.pickerStyle(.segmented).accessibilityIdentifier("gaugeUnit")
                VStack(alignment: .leading, spacing: 7) {
                    Text(L.t("定型前")).font(.subheadline.bold())
                    fields($before, prefix: "gaugeBefore", axes: countLabels)
                    Text(L.t("定型后")).font(.subheadline.bold())
                    fields($after, prefix: "gaugeAfter", axes: countLabels)
                }
                VStack(alignment: .leading, spacing: 7) {
                    Text(L.t("当前织片")).font(.subheadline.bold())
                    Picker(L.t("当前织片"), selection: $currentKind) {
                        Text(L.t("宽和长")).tag(GaugeInputKind.size)
                        Text(L.t("针数和行数")).tag(GaugeInputKind.counts)
                    }.pickerStyle(.segmented).accessibilityIdentifier("gaugeInputKind")
                    if currentKind == .size {
                        fields($size, prefix: "gaugeCurrentSize", axes: sizeLabels)
                    } else {
                        fields($counts, prefix: "gaugeCurrentCounts", axes: countLabels, whole: true)
                    }
                }
                VStack(alignment: .leading, spacing: 7) {
                    Text(L.t("目标尺寸（选填）")).font(.subheadline.bold())
                    fields($target, prefix: "gaugeTarget", axes: sizeLabels)
                }
                if !showSavedResultFirst { resultSection }
            }.padding(.top, 4).foregroundStyle(Design.ink)
        }
        .sheet(isPresented: $showingPaywall) { PaywallView() }
    }

    private var countLabels: (String, String) { (L.t("针数"), L.t("行数")) }
    private var sizeLabels: (String, String) { (L.f("宽（%@）", unitLabel), L.f("长（%@）", unitLabel)) }

    private func fields(_ values: Binding<GaugeValues>, prefix: String, axes: (String, String), whole: Bool = false) -> some View {
        HStack(spacing: 10) {
            CalculatorField(title: axes.0, id: prefix + "Across", value: values.across, focus: $focused, whole: whole)
            CalculatorField(title: axes.1, id: prefix + "Down", value: values.down, focus: $focused, whole: whole)
        }
    }

    @ViewBuilder private var resultSection: some View {
        if let record {
            let blocked = GaugeCalculator.blockedSize(record)
            let target = GaugeCalculator.targetCounts(record)
            if blocked != nil || target != nil {
                VStack(alignment: .leading, spacing: 8) {
                    if let blocked {
                        Text(L.f("定型后约 %@ × %@ %@", CalculatorNumber.text(blocked.across, digits: 2),
                                 CalculatorNumber.text(blocked.down, digits: 2), unitLabel))
                            .font(.headline).foregroundStyle(Design.accent).accessibilityIdentifier("gaugeSizeResult")
                    }
                    if let target {
                        Text(L.f("目标约需 %@ 针 × %@ 行", target.stitches.formatted(), target.rows.formatted()))
                            .font(.headline).foregroundStyle(Design.accent).accessibilityIdentifier("gaugeTargetResult")
                    }
                    if let projectID {
                        if saved == record {
                            Text(L.t("已存入作品")).font(.footnote).foregroundStyle(Design.secondary)
                                .accessibilityIdentifier("gaugeSaved")
                        } else {
                            Button {
                                if !model.hasPro { showingPaywall = true }
                                else if model.saveGauge(record, projectID: projectID) { saved = record }
                            } label: {
                                Text(L.t("存入作品")).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                            }.accessibilityIdentifier("saveGauge")
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).knitCard()
            }
        }
    }

    private func switchUnit(to newUnit: GaugeUnit) {
        let old = unit
        guard old != newUnit else { return }
        before.convert { old.convertSwatchCount($0, to: newUnit) }
        after.convert { old.convertSwatchCount($0, to: newUnit) }
        size.convert { old.convert($0, to: newUnit) }
        target.convert { old.convert($0, to: newUnit) }
        unit = newUnit
    }
}
