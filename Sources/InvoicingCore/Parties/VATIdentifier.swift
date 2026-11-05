/// A VAT identification number: the Czech DIČ ("CZ12345678") or another state's VAT ID ("DE123456789").
///
/// Only the shape is checked. For a Czech number the eight-digit form must pass the IČO check; the
/// nine- and ten-digit forms used by natural persons are accepted as digits. Whether a foreign number
/// is registered can only be confirmed online (VIES), which this offline app does not do; the
/// document validator asks the user to confirm it instead.
public struct VATIdentifier: Hashable, Sendable, CustomStringConvertible {
    /// Two-letter prefix as used for VAT: ISO 3166 country code, except Greece, which uses "EL".
    public let countryCode: String
    /// The part after the prefix, letters and digits only.
    public let number: String

    public init?(_ raw: String) {
        let compact = raw.uppercased().filter { !$0.isWhitespace && $0 != "-" && $0 != "." }
        guard (4...16).contains(compact.count) else { return nil }
        let prefix = String(compact.prefix(2))
        let rest = String(compact.dropFirst(2))
        guard prefix.allSatisfy({ $0.isASCII && $0.isLetter }) else { return nil }
        guard rest.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return nil }
        if prefix == "CZ", !Self.isValidCzechNumber(rest) { return nil }
        self.countryCode = prefix
        self.number = rest
    }

    /// The DIČ of a company: "CZ" followed by its IČO.
    public init(czech identificationNumber: IdentificationNumber) {
        self.countryCode = "CZ"
        self.number = identificationNumber.digits
    }

    static func isValidCzechNumber(_ number: String) -> Bool {
        guard number.allSatisfy(\.isASCIIDigit) else { return false }
        switch number.count {
        case 8: return IdentificationNumber.isValid(number)
        case 9, 10: return true
        default: return false
        }
    }

    /// "CZ12345678"
    public var value: String { countryCode + number }
    public var isCzech: Bool { countryCode == "CZ" }
    /// True for the 27 EU member states' prefixes (Greece as "EL"). Northern Ireland's "XI" is left out:
    /// it applies to goods only, and this app invoices services.
    public var isEU: Bool { Self.euPrefixes.contains(countryCode) }

    public static let euPrefixes: Set<String> = [
        "AT", "BE", "BG", "CY", "CZ", "DE", "DK", "EE", "EL", "ES", "FI", "FR", "HR", "HU",
        "IE", "IT", "LT", "LU", "LV", "MT", "NL", "PL", "PT", "RO", "SE", "SI", "SK",
    ]

    public var description: String { value }
}

extension VATIdentifier: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let identifier = VATIdentifier(text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid VAT identifier: \(text)")
        }
        self = identifier
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}
