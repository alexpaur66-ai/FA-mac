import Foundation

/// An amount in one currency. Arithmetic uses `Decimal`; nothing here ever touches `Double`.
/// Amounts are kept unrounded until `rounded()` is called, so intermediate math keeps its precision.
public struct Money: Hashable, Sendable, CustomStringConvertible {
    public let amount: Decimal
    public let currency: Currency

    public init(_ amount: Decimal, _ currency: Currency) {
        self.amount = amount
        self.currency = currency
    }

    /// Builds an amount from its integer minor units (cents, haléře), the storage form.
    public init(minorUnits: Int64, currency: Currency) {
        let scale = Decimal(sign: .plus, exponent: -currency.minorUnits, significand: 1)
        self.amount = Decimal(minorUnits) * scale
        self.currency = currency
    }

    public static func zero(_ currency: Currency) -> Money { Money(0, currency) }

    /// The amount rounded to the currency's minor units, half away from zero.
    public func rounded() -> Money { Money(amount.rounded(scale: currency.minorUnits), currency) }

    /// Integer minor units of the rounded amount, the storage form.
    /// Traps when the amount does not fit in `Int64`; use `minorUnitsIfRepresentable` to check first.
    public var minorUnits: Int64 {
        guard let value = minorUnitsIfRepresentable else {
            preconditionFailure("\(amount.plainString) \(currency.code) is outside the Int64 minor-unit range")
        }
        return value
    }

    /// Integer minor units of the rounded amount, or nil when they do not fit in `Int64`
    /// (an amount of roughly 9.2 × 10^16 CZK or more), instead of a silently wrong integer.
    public var minorUnitsIfRepresentable: Int64? {
        let scaled = amount.rounded(scale: currency.minorUnits) * Decimal(sign: .plus, exponent: currency.minorUnits, significand: 1)
        guard scaled >= Decimal(Int64.min), scaled <= Decimal(Int64.max) else { return nil }
        return NSDecimalNumber(decimal: scaled).int64Value
    }

    public var isZero: Bool { amount == 0 }
    public var isNegative: Bool { amount < 0 }

    public var description: String { "\(amount.rounded(scale: currency.minorUnits).plainString(minimumFractionDigits: currency.minorUnits)) \(currency.code)" }

    // MARK: Arithmetic (same currency only; mixing currencies is a programming error)

    public static func + (lhs: Money, rhs: Money) -> Money {
        precondition(lhs.currency == rhs.currency, "Cannot add \(lhs.currency) and \(rhs.currency)")
        return Money(lhs.amount + rhs.amount, lhs.currency)
    }

    public static func - (lhs: Money, rhs: Money) -> Money {
        precondition(lhs.currency == rhs.currency, "Cannot subtract \(rhs.currency) from \(lhs.currency)")
        return Money(lhs.amount - rhs.amount, lhs.currency)
    }

    public static prefix func - (value: Money) -> Money { Money(-value.amount, value.currency) }

    public static func * (lhs: Money, rhs: Decimal) -> Money { Money(lhs.amount * rhs, lhs.currency) }

    public static func += (lhs: inout Money, rhs: Money) { lhs = lhs + rhs }
    public static func -= (lhs: inout Money, rhs: Money) { lhs = lhs - rhs }

    /// Sums amounts that must all share one currency; an empty list gives zero in `currency`.
    public static func sum(_ values: [Money], in currency: Currency) -> Money {
        values.reduce(Money.zero(currency)) { $0 + $1 }
    }
}

extension Money: Codable {
    private enum CodingKeys: String, CodingKey { case amount, currency }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let text = try container.decode(String.self, forKey: .amount)
        guard let amount = Decimal(lenient: text) else {
            throw DecodingError.dataCorruptedError(forKey: .amount, in: container, debugDescription: "Not a decimal: \(text)")
        }
        self.init(amount, try container.decode(Currency.self, forKey: .currency))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(amount.plainString, forKey: .amount)
        try container.encode(currency, forKey: .currency)
    }
}
