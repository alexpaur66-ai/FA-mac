import Foundation

/// Parses the numbers a user types into the editor (quantities, prices, discounts, exchange rates)
/// in the locale's notation or the other common one. Anything that is not clearly a number is nil,
/// so a typo never silently becomes a different amount.
public enum DecimalInput {
    /// "1 234,50", "1234.5", "1,234.50", "1.234,50", "-5" and ".5" all parse. A separator groups
    /// thousands only when every group after it has exactly three digits, so "1.5." and "1,23,4" are
    /// nil rather than 15 and 1234. A lone separator is the decimal mark unless it is the locale's
    /// grouping separator in front of a three-digit group ("24,315" is 24315 in en_US, 24.315 in cs_CZ).
    public static func parse(_ text: String, locale: Locale) -> Decimal? {
        var cleaned = String(text.filter { !$0.isWhitespace }).replacingOccurrences(of: "\u{2212}", with: "-")
        guard !cleaned.isEmpty else { return nil }
        let separators = cleaned.filter { $0 == "," || $0 == "." }
        let kinds = Set(separators)
        if kinds.count == 2, let decimalMark = separators.last {
            // Both kinds: the last one is the decimal mark, the other one groups thousands.
            let grouping: Character = decimalMark == "," ? "." : ","
            guard separators.dropLast().allSatisfy({ $0 == grouping }),
                  groupsOfThree(cleaned, separator: grouping, decimalMark: decimalMark) else { return nil }
            cleaned = String(cleaned.filter { $0 != grouping }).replacingOccurrences(of: ",", with: ".")
        } else if let mark = separators.first {
            let grouped = groupsOfThree(cleaned, separator: mark, decimalMark: nil)
            if separators.count > 1 {
                guard grouped else { return nil }
                cleaned = String(cleaned.filter { $0 != mark })
            } else if grouped, String(mark) == locale.groupingSeparator {
                cleaned = String(cleaned.filter { $0 != mark })
            } else {
                cleaned = cleaned.replacingOccurrences(of: String(mark), with: ".")
            }
        }
        return plainDecimal(cleaned)
    }

    /// Exchange rates are never grouped and have decimals, so "24,315" is 24.315 in every locale.
    /// More than one separator is a typo.
    public static func parseRate(_ text: String) -> Decimal? {
        let cleaned = String(text.filter { !$0.isWhitespace }).replacingOccurrences(of: "\u{2212}", with: "-")
        guard !cleaned.isEmpty else { return nil }
        guard cleaned.filter({ $0 == "," || $0 == "." }).count <= 1 else { return nil }
        return plainDecimal(cleaned.replacingOccurrences(of: ",", with: "."))
    }

    /// `value` in the locale's notation, for messages that show what a valid entry looks like.
    public static func example(_ value: Decimal, locale: Locale, fractionLength: Int = 2) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = fractionLength
        formatter.maximumFractionDigits = fractionLength
        return formatter.string(from: value as NSDecimalNumber) ?? value.plainString(minimumFractionDigits: fractionLength)
    }

    /// True when the integer part of `text`, split at `separator`, is a leading group of one to three
    /// digits followed by groups of exactly three.
    private static func groupsOfThree(_ text: String, separator: Character, decimalMark: Character?) -> Bool {
        var integerPart = Substring(text)
        if let decimalMark, let index = text.lastIndex(of: decimalMark) { integerPart = text[..<index] }
        if integerPart.hasPrefix("-") { integerPart = integerPart.dropFirst() }
        let groups = integerPart.split(separator: separator, omittingEmptySubsequences: false)
        guard groups.count >= 2, (1...3).contains(groups[0].count) else { return false }
        return groups.dropFirst().allSatisfy { $0.count == 3 && $0.allSatisfy(\.isASCIIDigit) }
    }

    /// `cleaned` uses "." as the decimal mark and has no grouping; digits with an optional leading "-".
    private static func plainDecimal(_ cleaned: String) -> Decimal? {
        let unsigned = cleaned.hasPrefix("-") ? cleaned.dropFirst() : Substring(cleaned)
        let parts = unsigned.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2, parts.contains(where: { !$0.isEmpty }),
              parts.allSatisfy({ part in part.allSatisfy(\.isASCIIDigit) })
        else { return nil }
        return Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX"))
    }
}
