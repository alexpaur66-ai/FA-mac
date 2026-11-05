/// Czech identification number of a person or company (IČO, identifikační číslo osoby): eight digits
/// whose last digit is a weighted modulo-11 check digit. Printed with leading zeros, e.g. "00006947".
public struct IdentificationNumber: Hashable, Sendable, CustomStringConvertible {
    /// Exactly eight digits.
    public let digits: String

    /// Accepts up to eight digits with spaces; shorter input is padded with leading zeros.
    public init?(_ raw: String) {
        let compact = raw.filter { !$0.isWhitespace }
        guard !compact.isEmpty, compact.count <= 8, compact.allSatisfy(\.isASCIIDigit) else { return nil }
        let padded = compact.leftPadded(to: 8)
        guard Self.isValid(padded) else { return nil }
        self.digits = padded
    }

    /// The check used by the Czech registers: the first seven digits weighted 8…2, summed, and the
    /// remainder modulo 11 turned into the eighth digit as (11 − remainder) mod 10.
    static func isValid(_ digits: String) -> Bool {
        let values = digits.compactMap { $0.isASCIIDigit ? $0.wholeNumberValue : nil }
        guard values.count == 8, digits.count == 8 else { return false }
        let weighted = zip(values, [8, 7, 6, 5, 4, 3, 2]).reduce(0) { $0 + $1.0 * $1.1 }
        return (11 - weighted % 11) % 10 == values[7]
    }

    public var description: String { digits }
}

extension IdentificationNumber: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let number = IdentificationNumber(text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid IČO: \(text)")
        }
        self = number
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(digits)
    }
}
