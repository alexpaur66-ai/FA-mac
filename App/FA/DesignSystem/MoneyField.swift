// MoneyField: an editable amount (design-system.md §8.3): a plain number field with the currency code
// beside it, tabular digits, trailing alignment, never the currency format style. The field keeps the
// typed text and parses it with DecimalInput, so "1 234,50", "1234.5" and "1,234.50" all work, and a typo
// is reported inline instead of silently reverting to the last value.

import InvoicingCore
import SwiftUI

struct MoneyField: View {
    /// Nil while the text is empty or not a number.
    @Binding var amount: Decimal?
    /// ISO 4217 code shown after the field.
    let currency: String
    let label: LocalizedStringResource

    @Environment(\.locale) private var locale
    @State private var text = ""
    @FocusState private var focused: Bool

    private static let example = Decimal(string: "1234.5", locale: Locale(identifier: "en_US_POSIX")) ?? 1234

    var body: some View {
        LabeledContent {
            VStack(alignment: .trailing, spacing: Spacing.xs) {
                HStack(spacing: Spacing.s) {
                    TextField(text: $text) { Text(label) }
                        .labelsHidden()
                        .textRole(.amount)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 140)
                        .focused($focused)
                    Text(verbatim: currency).textRole(.body)
                }
                if isInvalid {
                    InlineMessage(L.enterNumber(DecimalInput.example(Self.example, locale: locale)))
                }
            }
        } label: {
            Text(label)
        }
        .onAppear {
            if text.isEmpty, let amount { text = Self.display(amount, locale: locale) }
        }
        .onChange(of: text) { _, newValue in
            amount = Self.parse(newValue, locale: locale)
        }
        .onChange(of: focused) { _, isFocused in
            // Leaving the field tidies a valid entry ("1234,5" becomes "1 234,50"); a typo stays visible.
            if !isFocused, let amount { text = Self.display(amount, locale: locale) }
        }
    }

    private var isInvalid: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && amount == nil
    }

    /// A positive number in either notation; zero and negative values are not an amount to record.
    static func parse(_ text: String, locale: Locale) -> Decimal? {
        guard let value = DecimalInput.parse(text, locale: locale), value > 0 else { return nil }
        return value
    }

    static func display(_ value: Decimal, locale: Locale) -> String {
        value.formatted(Decimal.FormatStyle(locale: locale).precision(.fractionLength(2)))
    }
}
