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

    /// How the rate for a day was found, so the editor can say which rate applies and why.
    public struct Resolution: Hashable, Sendable {
        public enum Rule: Hashable, Sendable {
            /// A rate stored for the requested day itself.
            case storedForDay
            /// The day is a weekend or a holiday: the rate of the last working day before it applies.
            case weekendOrHoliday
            /// A working day without a stored rate between two imported ČNB days: the ČNB published none
            /// that day, so the last published rate applies.
            case noPublicationThatDay
            /// No applicable rate is stored.
            case missing
        }

        public let requested: CalendarDay
        /// The day whose published rate applies: the day itself, or the last working day before it.
        public let publicationDay: CalendarDay
        public let rate: ExchangeRate?
        public let rule: Rule

        /// The earlier day whose rate stands in for the requested day, nil when the day has its own.
        public var fallbackFrom: CalendarDay? {
            guard let rate, rate.validFor != requested else { return nil }
            return rate.validFor
        }
    }

    /// The rate for `day`, under § 4 odst. 8 ZDPH: the day's own rate; on a weekend or holiday the last
    /// working day's rate; on a working day the ČNB skipped, the last imported rate before it. A rate
    /// stored for some other earlier day is never used, because it is not the rate valid on `day`.
    public func resolve(_ currency: Currency, on day: CalendarDay) -> Resolution {
        let publicationDay = CzechHolidays.lastWorkingDay(onOrBefore: day)
        let rates = byCurrency[currency.code] ?? [:]
        if let exact = rates[day] {
            return Resolution(requested: day, publicationDay: publicationDay, rate: exact, rule: .storedForDay)
        }
        if publicationDay != day {
            if let rate = rates[publicationDay] {
                return Resolution(requested: day, publicationDay: publicationDay, rate: rate, rule: .weekendOrHoliday)
            }
            return Resolution(requested: day, publicationDay: publicationDay, rate: nil, rule: .missing)
        }
        let previous = CzechHolidays.previousWorkingDay(before: day)
        let next = CzechHolidays.nextWorkingDay(after: day)
        if let before = rates[previous], before.isImportedFromCNB, rates[next]?.isImportedFromCNB == true {
            return Resolution(requested: day, publicationDay: publicationDay, rate: before, rule: .noPublicationThatDay)
        }
        return Resolution(requested: day, publicationDay: publicationDay, rate: nil, rule: .missing)
    }
}

private extension ExchangeRate {
    var isImportedFromCNB: Bool {
        if case .cnb = source { return true }
        return false
    }
}
