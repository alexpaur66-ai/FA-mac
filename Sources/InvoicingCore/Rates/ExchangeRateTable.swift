/// Exchange rates by currency and day, with the lookup rule the app uses for days without a
/// published rate (weekends, holidays): the last rate published on or before that day.
/// Whether that rule matches the company's accounting policy is for the accountant to confirm.
public struct ExchangeRateTable: Sendable, Hashable {
    public enum Lookup: Sendable {
        case exactDay
        case lastPublishedOnOrBefore
    }

    private var byCurrency: [String: [CalendarDay: ExchangeRate]] = [:]

    public init(rates: [ExchangeRate] = []) {
        merge(rates)
    }

    /// Adds rates; a rate for an existing currency and day replaces the old one.
    public mutating func merge(_ rates: [ExchangeRate]) {
        for rate in rates {
            byCurrency[rate.currency.code, default: [:]][rate.validFor] = rate
        }
    }

    public var isEmpty: Bool { byCurrency.values.allSatisfy { $0.isEmpty } }

    public var count: Int { byCurrency.values.reduce(0) { $0 + $1.count } }

    public func days(for currency: Currency) -> [CalendarDay] {
        (byCurrency[currency.code] ?? [:]).keys.sorted()
    }

    public func latestDay(for currency: Currency) -> CalendarDay? { days(for: currency).last }

    public func rate(for currency: Currency, on day: CalendarDay, lookup: Lookup = .lastPublishedOnOrBefore) -> ExchangeRate? {
        guard let rates = byCurrency[currency.code], !rates.isEmpty else { return nil }
        if let exact = rates[day] { return exact }
        guard lookup == .lastPublishedOnOrBefore else { return nil }
        guard let best = rates.keys.filter({ $0 < day }).max() else { return nil }
        return rates[best]
    }
}
