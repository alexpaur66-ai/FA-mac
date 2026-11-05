/// A SWIFT business identifier code (ISO 9362): 8 or 11 characters, letters and digits, stored uppercase.
/// Only the shape is checked; whether the code exists is not something an offline app can know.
public struct BIC: Hashable, Sendable, Codable, CustomStringConvertible {
    public let value: String

    public init?(_ raw: String) {
        let compact = raw.trimmingWhitespace().uppercased()
        guard compact.count == 8 || compact.count == 11 else { return nil }
        guard compact.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return nil }
        // Institution (4 letters), country (2 letters), location (2), optional branch (3).
        let characters = Array(compact)
        guard characters[0...5].allSatisfy(\.isLetter) else { return nil }
        self.value = compact
    }

    /// The ISO 3166 country code embedded in the BIC, e.g. "CZ" for RZBCCZPP.
    public var countryCode: String { String(value.dropFirst(4).prefix(2)) }

    public var description: String { value }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let bic = BIC(text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid BIC: \(text)")
        }
        self = bic
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}
