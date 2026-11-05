import Foundation

/// The kind of Czech VAT rate (§ 47 ZDPH). The percentage depends on the date, see `CzechVATRates`.
public enum VATRateKind: String, Sendable, Codable, CaseIterable {
    /// Základní sazba (21 % since 2013).
    case standard
    /// Snížená sazba (12 % since 1 Jan 2024; 15 % from 2013 to 2023).
    case reduced
    /// Druhá snížená sazba (10 %, in force 2015–2023 only).
    case secondReduced
    /// 0 % (used for the few supplies taxed at zero, for example books since 2024).
    case zero
}

/// A VAT rate with its percentage as in force on a given day.
public struct VATRate: Hashable, Sendable, Codable {
    public let kind: VATRateKind
    /// Whole-number percentage, e.g. 21.
    public let percent: Decimal

    public init(kind: VATRateKind, percent: Decimal) {
        self.kind = kind
        self.percent = percent
    }

    /// 0.21 for 21 %.
    public var multiplier: Decimal { percent / 100 }
    /// 1.21 for 21 %, the coefficient of § 37 písm. b) ZDPH for computing tax from a gross price.
    public var coefficient: Decimal { 1 + percent / 100 }
}

/// Czech VAT rates by period (§ 47 ZDPH and its amendments).
public enum CzechVATRates {
    private struct Period: Sendable {
        let from: CalendarDay
        let rates: [VATRateKind: Decimal]
    }

    private static let periods: [Period] = [
        Period(from: CalendarDay(year: 2013, month: 1, day: 1)!, rates: [.standard: 21, .reduced: 15, .zero: 0]),
        Period(from: CalendarDay(year: 2015, month: 1, day: 1)!, rates: [.standard: 21, .reduced: 15, .secondReduced: 10, .zero: 0]),
        Period(from: CalendarDay(year: 2024, month: 1, day: 1)!, rates: [.standard: 21, .reduced: 12, .zero: 0]),
    ]

    /// The rate of `kind` in force on `day`, or nil if that kind did not exist then.
    public static func rate(_ kind: VATRateKind, on day: CalendarDay) -> VATRate? {
        guard let period = periods.last(where: { $0.from <= day }), let percent = period.rates[kind] else { return nil }
        return VATRate(kind: kind, percent: percent)
    }

    /// All rates in force on `day`, standard first.
    public static func rates(on day: CalendarDay) -> [VATRate] {
        VATRateKind.allCases.compactMap { rate($0, on: day) }
    }
}
