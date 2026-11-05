import Foundation
@testable import InvoicingCore

/// Exact decimal from text. Tests never build a Decimal from a floating-point literal,
/// because `Decimal(0.1)` goes through Double and is not 0.1.
func d(_ text: String) -> Decimal {
    guard let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) else {
        fatalError("Not a decimal literal: \(text)")
    }
    return value
}

/// A calendar day from ISO text, for fixtures.
func day(_ iso: String) -> CalendarDay {
    guard let value = CalendarDay(iso: iso) else { fatalError("Not an ISO day: \(iso)") }
    return value
}
