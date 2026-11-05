/// A postal address as printed on a document: street line, postal code and city, country.
public struct PostalAddress: Hashable, Sendable, Codable {
    /// Street and number, e.g. "Dlouhá 12". May hold a second line separated by a newline.
    public var street: String
    public var city: String
    /// Czech codes are stored as five digits and printed as "110 00".
    public var postalCode: String
    /// ISO 3166-1 alpha-2, uppercase, e.g. "CZ".
    public var countryCode: String

    public init(street: String, city: String, postalCode: String, countryCode: String = "CZ") {
        self.street = street.trimmingWhitespace()
        self.city = city.trimmingWhitespace()
        self.countryCode = countryCode.trimmingWhitespace().uppercased()
        self.postalCode = Self.normalizePostalCode(postalCode, countryCode: self.countryCode)
    }

    public var isCzech: Bool { countryCode == "CZ" }

    /// True when a Czech postal code has its five digits; other countries are not checked.
    public var hasValidPostalCode: Bool {
        guard isCzech else { return !postalCode.isEmpty }
        return postalCode.count == 5 && postalCode.allSatisfy(\.isASCIIDigit)
    }

    /// "110 00" for Czech codes, otherwise the code as entered.
    public var formattedPostalCode: String {
        guard isCzech, hasValidPostalCode else { return postalCode }
        return String(postalCode.prefix(3)) + " " + String(postalCode.suffix(2))
    }

    /// The lines of the address block. The country line is added for foreign addresses, or always
    /// when `alwaysIncludeCountry` is set (documents for foreign customers name the supplier's country too).
    /// `countryName` is the localized country name; when nil the ISO code is printed.
    public func lines(countryName: String? = nil, alwaysIncludeCountry: Bool = false) -> [String] {
        var lines = street.split(separator: "\n").map { String($0).trimmingWhitespace() }.filter { !$0.isEmpty }
        let cityLine = [formattedPostalCode, city].filter { !$0.isEmpty }.joined(separator: " ")
        if !cityLine.isEmpty { lines.append(cityLine) }
        if alwaysIncludeCountry || !isCzech {
            lines.append(countryName ?? countryCode)
        }
        return lines
    }

    static func normalizePostalCode(_ code: String, countryCode: String) -> String {
        let trimmed = code.trimmingWhitespace()
        guard countryCode == "CZ" else { return trimmed }
        let digits = trimmed.filter(\.isASCIIDigit)
        return digits.count == 5 && digits.count == trimmed.filter({ !$0.isWhitespace }).count ? digits : trimmed
    }
}
