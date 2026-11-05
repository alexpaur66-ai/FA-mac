/// Czech payment symbols: variabilní, specifický and konstantní symbol. Digits only, at most 10.
public struct PaymentSymbol: Hashable, Sendable, Codable, CustomStringConvertible {
    public enum Kind: String, Sendable, Codable {
        case variable, specific, constant
    }

    public let kind: Kind
    public let digits: String

    public init?(_ kind: Kind, _ text: String) {
        let cleaned = text.trimmingWhitespace()
        guard !cleaned.isEmpty, cleaned.count <= 10, cleaned.allSatisfy(\.isASCIIDigit) else { return nil }
        self.kind = kind
        self.digits = cleaned
    }

    public static func variable(_ text: String) -> PaymentSymbol? { PaymentSymbol(.variable, text) }
    public static func specific(_ text: String) -> PaymentSymbol? { PaymentSymbol(.specific, text) }
    public static func constant(_ text: String) -> PaymentSymbol? { PaymentSymbol(.constant, text) }

    /// The variable symbol Czech payers expect for a document: its number with everything but
    /// digits removed, the last 10 digits at most. "FV-2026-001" → "2026001".
    public static func variable(fromDocumentNumber number: String) -> PaymentSymbol? {
        let digits = number.filter(\.isASCIIDigit)
        guard !digits.isEmpty else { return nil }
        return PaymentSymbol(.variable, String(digits.suffix(10)))
    }

    /// Digits without leading zeros, which banks treat as insignificant; "0" when all zeros.
    public var canonical: String {
        let stripped = digits.drop(while: { $0 == "0" })
        return stripped.isEmpty ? "0" : String(stripped)
    }

    public var description: String { digits }
}
