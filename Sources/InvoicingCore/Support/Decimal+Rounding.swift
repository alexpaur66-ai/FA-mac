import Foundation

extension Decimal {
    /// Rounds to `scale` decimal places. The default `.plain` mode rounds half away from zero,
    /// which is the Czech "matematické zaokrouhlení" used for amounts on documents.
    public func rounded(scale: Int, mode: NSDecimalNumber.RoundingMode = .plain) -> Decimal {
        var value = self
        var result = Decimal()
        NSDecimalRound(&result, &value, scale, mode)
        return result
    }

    /// Parses a decimal written with a dot or a comma as the decimal separator
    /// ("24,310", "24.310", "-1 234,5" with spaces as thousands separators). Nil for anything else.
    public init?(lenient text: String) {
        var normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized = normalized.replacingOccurrences(of: " ", with: "")
        normalized = normalized.replacingOccurrences(of: "\u{00A0}", with: "")
        normalized = normalized.replacingOccurrences(of: ",", with: ".")
        guard !normalized.isEmpty else { return nil }
        var seenDot = false
        var seenDigit = false
        for (index, character) in normalized.enumerated() {
            if character == "-" && index == 0 { continue }
            if character == "." && !seenDot { seenDot = true; continue }
            guard character.isASCII, character.isNumber else { return nil }
            seenDigit = true
        }
        guard seenDigit, let value = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        self = value
    }

    /// Plain notation with a dot and no exponent, e.g. "24.31". Safe for storage and for exact round trips.
    /// Trailing zeros are not guaranteed either way; use `plainString(minimumFractionDigits:)` for display.
    public var plainString: String {
        NSDecimalNumber(decimal: self).description(withLocale: Locale(identifier: "en_US_POSIX"))
    }

    /// `plainString` padded with zeros to at least `minimumFractionDigits` decimals: 24.31 → "24.310" for 3.
    public func plainString(minimumFractionDigits: Int) -> String {
        let text = plainString
        guard minimumFractionDigits > 0 else { return text }
        if let dot = text.firstIndex(of: ".") {
            let fractionDigits = text.distance(from: text.index(after: dot), to: text.endIndex)
            guard fractionDigits < minimumFractionDigits else { return text }
            return text + String(repeating: "0", count: minimumFractionDigits - fractionDigits)
        }
        return text + "." + String(repeating: "0", count: minimumFractionDigits)
    }

    /// True when the value has no fractional part beyond `scale` decimals.
    public func fits(scale: Int) -> Bool { self == rounded(scale: scale) }
}
