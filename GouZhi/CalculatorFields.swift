import SwiftUI

enum CalculatorNumber {
    static func decimal(_ text: String) -> Decimal? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let separator = Locale.current.decimalSeparator ?? "."
        let normalized = value.replacingOccurrences(of: separator, with: ".")
        guard normalized.range(of: #"^-?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)$"#, options: .regularExpression) != nil,
              let number = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")),
              !number.isNaN else { return nil }
        return number
    }

    static func text(_ value: Decimal) -> String {
        value.formatted(.number.grouping(.never).precision(.fractionLength(0...12)))
    }

    static func text(_ value: Double, digits: Int = 6) -> String {
        value.formatted(.number.grouping(.never).precision(.fractionLength(0...digits)))
    }
}

struct CalculatorField: View {
    var title: String
    var id: String
    @Binding var value: String
    var focus: FocusState<String?>.Binding
    var placeholder = "—"
    var whole = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(Design.secondary)
            TextField(title, text: $value, prompt: Text(placeholder))
                .focused(focus, equals: id)
                .keyboardType(whole ? .numberPad : .decimalPad)
                .font(.body.monospacedDigit())
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(Design.card, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityIdentifier(id)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CalculatorSheet<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    var title: String
    var finishInput: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        NavigationStack {
            ScrollView {
                content.padding(.horizontal, 16).padding(.bottom, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .accessibilityIdentifier("calculatorForm")
            .background(Design.background)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Text(L.t("关闭")).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                    }.accessibilityIdentifier("closeCalculator")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(L.t("完成输入"), action: finishInput).accessibilityIdentifier("finishCalculatorInput")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
