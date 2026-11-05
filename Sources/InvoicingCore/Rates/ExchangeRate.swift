import Foundation

/// Where an exchange rate came from. Kept on every document so the conversion can be explained years later.
public enum ExchangeRateSource: Hashable, Sendable, Codable {
    /// Kurz devizového trhu vyhlášený ČNB; `order` is the ČNB sequence number of the day (nil when unknown).
    case cnb(order: Int?)
    /// Referenční směnný kurz ECB (§ 4 odst. 8 písm. a) bod 2 ZDPH).
    case ecb
    /// Typed in by the user.
    case manual
    /// A fixed rate set by the company's accounting policy (pevný kurz).
    case fixedAccounting
}

/// A foreign-currency rate against CZK, quoted the ČNB way: `amount` units of `currency` = `czkPerAmount` CZK.
public struct ExchangeRate: Hashable, Sendable, Codable {
    public let currency: Currency
    /// 1 for EUR, 100 for HUF or JPY, 1000 for IDR: the quantity the rate is quoted for.
    public let amount: Int
    /// CZK for `amount` units, e.g. 24.310 for 1 EUR.
    public let czkPerAmount: Decimal
    /// The day the rate was published for (§ 4 odst. 8 ZDPH: the rate valid on the day the obligation arises).
    public let validFor: CalendarDay
    public let source: ExchangeRateSource

    public init(currency: Currency, amount: Int = 1, czkPerAmount: Decimal, validFor: CalendarDay, source: ExchangeRateSource) {
        precondition(amount > 0, "Rate amount must be positive")
        self.currency = currency
        self.amount = amount
        self.czkPerAmount = czkPerAmount
        self.validFor = validFor
        self.source = source
    }

    /// CZK for one unit of the currency, unrounded.
    public var czkPerUnit: Decimal { czkPerAmount / Decimal(amount) }

    /// Converts `money` (which must be in this rate's currency) to CZK, rounded to haléře.
    public func toCZK(_ money: Money) -> Money {
        precondition(money.currency == currency, "Rate is for \(currency), amount is in \(money.currency)")
        let czk = money.amount * czkPerAmount / Decimal(amount)
        return Money(czk, .czk).rounded()
    }

    /// Converts a plain decimal in this rate's currency to CZK, rounded to `scale` decimals.
    public func toCZK(_ value: Decimal, scale: Int = 2) -> Decimal {
        (value * czkPerAmount / Decimal(amount)).rounded(scale: scale)
    }

    /// "24,310 CZK/EUR" in Czech notation, for printing on documents.
    public var czechLabel: String {
        let rateText = czkPerAmount.plainString(minimumFractionDigits: 3).replacingOccurrences(of: ".", with: ",")
        return amount == 1 ? "\(rateText) CZK/\(currency.code)" : "\(rateText) CZK/\(amount) \(currency.code)"
    }
}
