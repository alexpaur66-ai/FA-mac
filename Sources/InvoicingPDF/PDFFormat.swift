import Foundation
import InvoicingCore

/// Czech number and date formats for both document languages: the PDF locale is `cs_CZ` and the English
/// gloss changes words, never number formats (design-system.md §9). Nothing here builds a format by hand.
enum PDFFormat {
    static let locale = Locale(identifier: "cs_CZ")

    /// "1 234,50 €", "12 100,00 Kč", "−6 050,00 €".
    static func money(_ amount: Decimal, _ currency: Currency) -> String {
        amount.formatted(
            Decimal.FormatStyle.Currency(code: currency.code, locale: locale)
                .precision(.fractionLength(currency.minorUnits))
                .rounded(rule: .toNearestOrAwayFromZero)
        )
    }

    /// Quantities and rates: up to `maximumFractionDigits` decimals, trailing zeros dropped ("10", "1,5").
    static func number(_ value: Decimal, maximumFractionDigits: Int = 3) -> String {
        value.formatted(
            Decimal.FormatStyle(locale: locale)
                .precision(.fractionLength(0...maximumFractionDigits))
                .rounded(rule: .toNearestOrAwayFromZero)
        )
    }

    /// "21 %" with the Czech non-breaking space before the sign.
    static func percent(_ value: Decimal) -> String {
        number(value, maximumFractionDigits: 2) + "\u{00A0}%"
    }

    /// "5. 11. 2026".
    static func day(_ day: CalendarDay) -> String { day.czechString }
}
