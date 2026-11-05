/// An ISO 11649 structured creditor reference ("RF18 5390 0754 7034"): the reference a SEPA payer's
/// bank passes to the beneficiary unchanged, so an EU customer's payment can be matched to the invoice
/// automatically. "RF" + two check digits + 1–21 letters or digits; the check is the IBAN mod-97 rule.
public struct CreditorReference: Hashable, Sendable, CustomStringConvertible {
    /// Compact uppercase form, e.g. "RF602026001".
    public let value: String

    /// Validates an existing reference; accepts spaces and lowercase.
    public init?(_ raw: String) {
        let compact = raw.uppercased().filter { !$0.isWhitespace }
        guard (5...25).contains(compact.count), compact.hasPrefix("RF") else { return nil }
        guard compact.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return nil }
        guard IBAN.mod97(compact) == 1 else { return nil }
        self.value = compact
    }

    /// Builds the reference for `reference` (1–21 letters or digits), e.g. "2026001" → "RF602026001".
    public init?(reference: String) {
        let compact = reference.uppercased().filter { !$0.isWhitespace }
        guard (1...21).contains(compact.count), compact.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return nil }
        // ISO 11649: check digits = 98 − (reference followed by "RF00") mod 97. IBAN.mod97 moves the
        // first four characters to the end, so "RF00" + reference is exactly that string.
        let check = 98 - IBAN.mod97("RF00" + compact)
        self.value = "RF" + String(check).leftPadded(to: 2) + compact
    }

    /// The reference without "RF" and the check digits.
    public var reference: String { String(value.dropFirst(4)) }

    /// "RF18 5390 0754 7034"
    public var formatted: String {
        var groups: [String] = []
        var rest = Substring(value)
        while !rest.isEmpty {
            groups.append(String(rest.prefix(4)))
            rest = rest.dropFirst(4)
        }
        return groups.joined(separator: " ")
    }

    public var description: String { value }
}

extension CreditorReference: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let reference = CreditorReference(text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid creditor reference: \(text)")
        }
        self = reference
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}
