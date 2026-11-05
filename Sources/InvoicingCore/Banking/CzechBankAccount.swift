/// A Czech domestic account number "prefix-number/bankCode" with the modulo-11 check used by Czech banks.
public struct CzechBankAccount: Hashable, Sendable, Codable, CustomStringConvertible {
    /// Up to 6 digits without leading zeros; empty when the account has no prefix.
    public let prefix: String
    /// 2 to 10 digits without leading zeros.
    public let number: String
    /// Exactly 4 digits, e.g. "5500" for Raiffeisenbank.
    public let bankCode: String

    public init?(prefix: String = "", number: String, bankCode: String) {
        let cleanPrefix = Self.stripLeadingZeros(prefix.trimmingWhitespace())
        let cleanNumber = Self.stripLeadingZeros(number.trimmingWhitespace())
        let cleanBank = bankCode.trimmingWhitespace()
        guard cleanPrefix.count <= 6, cleanPrefix.allSatisfy(\.isASCIIDigit) else { return nil }
        guard (1...10).contains(cleanNumber.count), cleanNumber.allSatisfy(\.isASCIIDigit) else { return nil }
        guard cleanBank.count == 4, cleanBank.allSatisfy(\.isASCIIDigit) else { return nil }
        guard Self.checksumValid(cleanNumber.leftPadded(to: 10), weights: Self.numberWeights) else { return nil }
        if !cleanPrefix.isEmpty {
            guard Self.checksumValid(cleanPrefix.leftPadded(to: 6), weights: Self.prefixWeights) else { return nil }
        }
        self.prefix = cleanPrefix
        self.number = cleanNumber
        self.bankCode = cleanBank
    }

    /// Parses "19-2000145399/0800" or "2000145399/0800".
    public init?(parsing text: String) {
        let parts = text.trimmingWhitespace().split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let accountParts = parts[0].split(separator: "-", omittingEmptySubsequences: false)
        switch accountParts.count {
        case 1: self.init(number: String(accountParts[0]), bankCode: String(parts[1]))
        case 2: self.init(prefix: String(accountParts[0]), number: String(accountParts[1]), bankCode: String(parts[1]))
        default: return nil
        }
    }

    /// Prefix padded to 6 digits, as used inside the IBAN.
    public var paddedPrefix: String { prefix.leftPadded(to: 6) }
    /// Number padded to 10 digits, as used inside the IBAN.
    public var paddedNumber: String { number.leftPadded(to: 10) }

    /// "19-2000145399/0800" or "2000145399/0800".
    public var description: String { prefix.isEmpty ? "\(number)/\(bankCode)" : "\(prefix)-\(number)/\(bankCode)" }

    // MARK: Checksum (weights published for Czech account numbers, modulo 11)

    private static let numberWeights = [6, 3, 7, 9, 10, 5, 8, 4, 2, 1]
    private static let prefixWeights = [10, 5, 8, 4, 2, 1]

    private static func checksumValid(_ digits: String, weights: [Int]) -> Bool {
        guard digits.count == weights.count else { return false }
        let sum = zip(digits, weights).reduce(0) { partial, pair in
            partial + (pair.0.wholeNumberValue ?? 0) * pair.1
        }
        return sum % 11 == 0
    }

    /// Leading zeros are not significant; an all-zero prefix is no prefix, an all-zero number is invalid.
    private static func stripLeadingZeros(_ text: String) -> String {
        String(text.drop(while: { $0 == "0" }))
    }
}
