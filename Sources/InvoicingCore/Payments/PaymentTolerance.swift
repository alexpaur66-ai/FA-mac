import Foundation

/// The one fixed payment tolerance (screens-flows.md §2f Record Payment), shared with the v0.2 bank matching:
/// ±1 Kč for CZK, one minor unit (0,01) for EUR, USD and every other currency, until the accountant answers
/// (ACCT). It is a rule, not a setting.
public enum PaymentTolerance {
    /// The largest difference that still counts as the same amount.
    public static func amount(for currency: Currency) -> Decimal {
        currency == .czk ? 1 : Decimal(sign: .plus, exponent: -currency.minorUnits, significand: 1)
    }

    /// True when both amounts are in the same currency and differ by at most the tolerance.
    public static func matches(_ first: Money, _ second: Money) -> Bool {
        first.currency == second.currency && (first.amount - second.amount).magnitude <= amount(for: first.currency)
    }
}
