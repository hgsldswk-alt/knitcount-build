import OSLog
import SwiftUI

struct YarnDraft: Equatable {
    struct Context: Hashable {
        var partID: UUID
        var copy: Int

        init(part: Part) {
            partID = part.id
            copy = part.currentCopy
        }
    }

    struct Amount: Equatable {
        var text = ""
        var value: Decimal?

        mutating func enter(_ input: String, in unit: YarnUnit) {
            text = input
            value = CalculatorNumber.decimal(input).flatMap { unit.convert($0, to: unit == .grams ? .grams : .metres) }
        }

        mutating func showLength(in unit: YarnUnit) {
            if let value, let display = YarnUnit.metres.convert(value, to: unit) {
                text = CalculatorNumber.text(display)
            }
        }
    }

    var unit: YarnUnit
    var before = Amount()
    var after = Amount()
    var reserve = Amount()
    var worked: String?
    var startingRows: Int?
    var sampledRows: Int?
    var measuredAtRow: Int?
}

struct YarnEstimateSheet: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let part = model.part
        let context = YarnDraft.Context(part: part)
        let preference = model.isolated ? nil : UserDefaults.standard.string(forKey: YarnEstimateForm.unitKey)
        let unit = preference.flatMap(YarnUnit.init(rawValue:)) ?? .grams
        YarnEstimateForm(part: part, projectName: model.project?.name, history: model.data.undo[part.historyKey] ?? [],
                         draft: model.yarnDrafts[context] ?? YarnDraft(unit: unit))
            .id(context)
    }
}

private struct YarnEstimateForm: View {
    static let unitKey = "yarnEstimate.unit"
    private static let logger = Logger(subsystem: "com.hgsldswk.knitcount", category: "sharing")
    @EnvironmentObject private var model: AppModel
    @FocusState private var focused: String?
    @State private var draft: YarnDraft
    @State private var preview: YarnShareResult?
    private let part: Part
    private let projectName: String?
    private let history: [UndoStep]

    init(part: Part, projectName: String?, history: [UndoStep], draft: YarnDraft) {
        self.part = part
        self.projectName = projectName
        self.history = history
        _draft = State(initialValue: draft)
    }

    private var completedRows: Int { max(part.rowsWorked, max(1, part.row) - 1) }
    private var automaticRows: Int {
        if let start = draft.startingRows, completedRows > start { return completedRows - start }
        let prior = history.reversed().compactMap { step -> Int? in
            guard let row = step.counters.first(where: { $0.kind == .row })?.value else { return nil }
            let value = max(step.rowsWorked, max(1, row) - 1)
            return value < completedRows ? value : nil
        }.prefix(5).min()
        return prior.map { max(1, min(5, completedRows - $0)) } ?? 5
    }

    private var remaining: Int? {
        guard projectName != nil, part.counters.contains(where: { $0.kind == .row }) else { return nil }
        let lastRow = max(part.roundTargets.keys.max() ?? 0,
                          part.textPattern?.compactMap(\.row).max() ?? 0,
                          part.patternPages.compactMap { $0.rowMap.keys.max() }.max() ?? 0)
        return YarnEstimate.remainingRows(lastRow: lastRow, currentRow: draft.measuredAtRow ?? part.row)
    }

    private var result: YarnShareResult? {
        guard let before = draft.before.value,
              let after = draft.after.value,
              let worked = Int(draft.worked ?? String(draft.sampledRows ?? automaticRows)),
              let reserve = draft.reserve.text.isEmpty ? Decimal(0) : draft.reserve.value,
              let rows = YarnEstimate.rows(before: before, after: after, worked: worked, reserve: reserve) else { return nil }
        return YarnShareResult(rows: rows, remaining: remaining, projectName: projectName)
    }

    var body: some View {
        CalculatorSheet(title: L.t("余线够吗"), finishInput: { focused = nil }) {
            VStack(alignment: .leading, spacing: 10) {
                Picker(L.t("用线单位"), selection: Binding(get: { draft.unit }, set: switchUnit)) {
                    Text("g").tag(YarnUnit.grams)
                    Text("m").tag(YarnUnit.metres)
                    Text("yd").tag(YarnUnit.yards)
                }.pickerStyle(.segmented).accessibilityIdentifier("yarnUnit")

                HStack(spacing: 10) {
                    CalculatorField(title: L.t("织前余线"), id: "yarnBefore", value: measurement(\.before),
                                    focus: $focused, placeholder: "0")
                    CalculatorField(title: L.t("织后余线"), id: "yarnAfter", value: measurement(\.after),
                                    focus: $focused, placeholder: "0")
                }
                HStack(spacing: 10) {
                    CalculatorField(title: L.t("测量间织了几行"), id: "yarnWorked",
                                    value: Binding(get: { draft.worked ?? String(draft.sampledRows ?? automaticRows) },
                                                   set: { draft.worked = $0 }),
                                    focus: $focused, whole: true)
                    CalculatorField(title: L.t("收边预留"), id: "yarnReserve", value: measurement(\.reserve),
                                    focus: $focused, placeholder: "0")
                }

                if let result {
                    resultPanel(result)
                } else {
                    Text(draft.before.text.isEmpty || draft.after.text.isEmpty
                         ? L.t("记下织前余线，织几行再填织后余线。")
                         : L.t("织前余线须大于织后余线，行数须大于零，预留不能为负。"))
                        .font(.footnote).foregroundStyle(Design.secondary)
                }
            }.padding(.top, 4)
        }
        .task {
            if draft.before.text.isEmpty { focused = "yarnBefore" }
            else if draft.after.text.isEmpty { focused = "yarnAfter" }
        }
        .onChange(of: draft) { _, value in model.yarnDrafts[YarnDraft.Context(part: part)] = value }
        .onChange(of: focused) { _, value in
            if value != "yarnWorked" && draft.worked == "" { draft.worked = nil }
        }
        .sheet(item: $preview) { YarnSharePreview(result: $0) }
    }

    private func resultPanel(_ result: YarnShareResult) -> some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(result.headline)
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .foregroundStyle(Design.accent)
                    .accessibilityIdentifier("yarnResult")
                if let comparison = result.comparison {
                    Text(comparison).font(.footnote).foregroundStyle(Design.secondary)
                        .accessibilityIdentifier("yarnComparison")
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Button {
                focused = nil
                Self.logger.info("share.requested")
                preview = result
            } label: {
                Image(systemName: "square.and.arrow.up").frame(width: 44, height: 44).contentShape(Rectangle())
            }.accessibilityLabel(L.t("分享")).accessibilityIdentifier("previewYarnShare")
        }.padding(.leading, 12).padding(.trailing, 4).padding(.vertical, 5)
            .background(Design.card, in: RoundedRectangle(cornerRadius: 14))
    }

    private func measurement(_ key: WritableKeyPath<YarnDraft, YarnDraft.Amount>) -> Binding<String> {
        Binding(get: { draft[keyPath: key].text }, set: { value in
            guard draft[keyPath: key].text != value else { return }
            let unit = draft.unit
            draft[keyPath: key].enter(value, in: unit)
            if key == \.before {
                draft.startingRows = value.isEmpty ? nil : completedRows
            } else if key == \.after {
                draft.sampledRows = value.isEmpty ? nil : automaticRows
                draft.measuredAtRow = value.isEmpty ? nil : part.row
            }
        })
    }

    private func switchUnit(to unit: YarnUnit) {
        let old = draft.unit
        guard old != unit else { return }
        var updated = draft
        updated.unit = unit
        if old == .grams || unit == .grams {
            updated.before = .init()
            updated.after = .init()
            updated.reserve = .init()
            updated.startingRows = nil
            updated.sampledRows = nil
            updated.measuredAtRow = nil
        } else {
            updated.before.showLength(in: unit)
            updated.after.showLength(in: unit)
            updated.reserve.showLength(in: unit)
        }
        draft = updated
        if !model.isolated { UserDefaults.standard.set(unit.rawValue, forKey: Self.unitKey) }
    }
}
