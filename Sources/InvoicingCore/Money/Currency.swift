/// An ISO 4217 currency with the number of minor units (2 for CZK and EUR).
public struct Currency: Hashable, Sendable, CustomStringConvertible {
    public let code: String
    public let minorUnits: Int

    public init(code: String, minorUnits: Int = 2) {
        self.code = code.uppercased()
        self.minorUnits = minorUnits
    }

    public static let czk = Currency(code: "CZK")
    public static let eur = Currency(code: "EUR")
    public static let usd = Currency(code: "USD")
    public static let gbp = Currency(code: "GBP")
    public static let chf = Currency(code: "CHF")
    public static let pln = Currency(code: "PLN")

    /// Minor units for the currencies the ČNB publishes; everything else defaults to 2.
    public static func known(_ code: String) -> Currency {
        let upper = code.uppercased()
        switch upper {
        case "JPY", "KRW", "ISK": return Currency(code: upper, minorUnits: 0)
        default: return Currency(code: upper, minorUnits: 2)
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
