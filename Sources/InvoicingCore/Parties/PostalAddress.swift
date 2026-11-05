/// A postal address as printed on a document: street line, postal code and city, country.
public struct PostalAddress: Hashable, Sendable, Codable {
    /// Street and number, e.g. "Dlouhá 12". May hold a second line separated by a newline (any kind,
    /// "\r\n" from pasted Windows text included).
    public var street: String
    public var city: String
    /// Czech codes are stored as five digits and printed as "110 00".
    public var postalCode: String
    /// ISO 3166-1 alpha-2, uppercase, e.g. "CZ".
    public var countryCode: String

    public init(street: String, city: String, postalCode: String, countryCode: String = "CZ") {
        self.street = street.trimmingWhitespace()
        self.city = city.trimmingWhitespace()
        self.countryCode = Self.normalizeCountryCode(countryCode)
        self.postalCode = Self.normalizePostalCode(postalCode, countryCode: self.countryCode)
    }

    /// Also true for a code set through the public setter in another case or with spaces ("cz").
    public var isCzech: Bool { Self.normalizeCountryCode(countryCode) == "CZ" }

    /// True when a Czech postal code has its five digits; other countries are not checked.
    public var hasValidPostalCode: Bool {
        guard isCzech else { return !postalCode.isEmpty }
        let code = Self.normalizePostalCode(postalCode, countryCode: "CZ")
        return code.count == 5 && code.allSatisfy(\.isASCIIDigit)
    }

    /// "110 00" for Czech codes, otherwise the code as entered.
    public var formattedPostalCode: String {
        guard isCzech, hasValidPostalCode else { return postalCode }
        let code = Self.normalizePostalCode(postalCode, countryCode: "CZ")
        return String(code.prefix(3)) + " " + String(code.suffix(2))
    }

    /// The lines of the address block. The country line is added for foreign addresses, or always
    /// when `alwaysIncludeCountry` is set (documents for foreign customers name the supplier's country too).
    /// `countryName` is the localized country name; when nil the ISO code is printed.
    public func lines(countryName: String? = nil, alwaysIncludeCountry: Bool = false) -> [String] {
        var lines = street.split(whereSeparator: \.isNewline).map { String($0).trimmingWhitespace() }.filter { !$0.isEmpty }
        let cityLine = [formattedPostalCode, city].filter { !$0.isEmpty }.joined(separator: " ")
        if !cityLine.isEmpty { lines.append(cityLine) }
        if alwaysIncludeCountry || !isCzech {
            lines.append(countryName ?? Self.normalizeCountryCode(countryCode))
        }
        return lines
    }

    static func normalizeCountryCode(_ code: String) -> String {
        code.trimmingWhitespace().uppercased()
    }

    static func normalizePostalCode(_ code: String, countryCode: String) -> String {
        let trimmed = code.trimmingWhitespace()
        guard normalizeCountryCode(countryCode) == "CZ" else { return trimmed }
        let digits = trimmed.filter(\.isASCIIDigit)
        return digits.count == 5 && digits.count == trimmed.filter({ !$0.isWhitespace }).count ? digits : trimmed
    }
}

extension PostalAddress {
    private enum CodingKeys: String, CodingKey {
        case street, city, postalCode, countryCode
    }

    /// Decodes through the normalising initialiser, so stored data gets the same trimming, uppercase
    /// country code and five-digit Czech postal code as values built in code.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let street = try container.decode(String.self, forKey: .street)
        let city = try container.decode(String.self, forKey: .city)
        let postalCode = try container.decode(String.self, forKey: .postalCode)
        let countryCode = try container.decode(String.self, forKey: .countryCode)
        self.init(street: street, city: city, postalCode: postalCode, countryCode: countryCode)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(street, forKey: .street)
        try container.encode(city, forKey: .city)
        try container.encode(postalCode, forKey: .postalCode)
        try container.encode(countryCode, forKey: .countryCode)
    }
}
