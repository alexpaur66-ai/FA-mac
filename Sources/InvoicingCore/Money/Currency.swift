/// An ISO 4217 currency with the number of minor units (2 for CZK and EUR).
/// The minor units always follow from the code, so two values with the same code are equal and
/// `Money(minorUnits:currency:)` scales the same way whichever way the currency was built.
public struct Currency: Hashable, Sendable, CustomStringConvertible {
    public let code: String
    public let minorUnits: Int

    public init(code: String) {
        let upper = code.uppercased()
        self.code = upper
        self.minorUnits = Currency.defaultMinorUnits(for: upper)
    }

    public static let czk = Currency(code: "CZK")
    public static let eur = Currency(code: "EUR")
    public static let usd = Currency(code: "USD")
    public static let gbp = Currency(code: "GBP")
    public static let chf = Currency(code: "CHF")
    public static let pln = Currency(code: "PLN")

    /// Same as `Currency(code:)`; kept for existing callers.
    public static func known(_ code: String) -> Currency {
        Currency(code: code)
    }

    /// Minor units for the currencies the ČNB publishes: 0 for JPY, KRW and ISK, 2 for everything else.
    private static func defaultMinorUnits(for upperCode: String) -> Int {
        switch upperCode {
        case "JPY", "KRW", "ISK": return 0
        default: return 2
        }
    }

    public var description: String { code }
}

extension Currency: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = Currency.known(try container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(code)
    }
}
