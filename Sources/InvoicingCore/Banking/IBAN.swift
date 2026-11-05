/// An IBAN validated with the ISO 13616 mod-97 check, stored compact and uppercase.
public struct IBAN: Hashable, Sendable, CustomStringConvertible {
    public let value: String

    /// Accepts spaces and lowercase; nil when the format or the check digits are wrong.
    public init?(_ raw: String) {
        let compact = raw.uppercased().filter { !$0.isWhitespace }
        guard (15...34).contains(compact.count) else { return nil }
        guard compact.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return nil }
        let characters = Array(compact)
        guard characters[0].isLetter, characters[1].isLetter, characters[2].isNumber, characters[3].isNumber else { return nil }
        guard Self.mod97(compact) == 1 else { return nil }
        self.value = compact
    }

    public var countryCode: String { String(value.prefix(2)) }
    public var checkDigits: String { String(value.dropFirst(2).prefix(2)) }
    public var bban: String { String(value.dropFirst(4)) }

    /// "CZ65 0800 0000 1920 0014 5399"
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

    /// Builds a Czech IBAN from a domestic account number. The BBAN is bank code (4) + prefix (6) + number (10).
    public static func czech(_ account: CzechBankAccount) -> IBAN? {
        let bban = account.bankCode + account.paddedPrefix + account.paddedNumber
        let check = 98 - mod97("CZ00" + bban)
        let checkText = check < 10 ? "0\(check)" : "\(check)"
        return IBAN("CZ" + checkText + bban)
    }

    /// The domestic account number for a Czech IBAN; nil for other countries or an invalid checksum.
    public var czechAccount: CzechBankAccount? {
        guard countryCode == "CZ", bban.count == 20 else { return nil }
        let bankCode = String(bban.prefix(4))
        let prefix = String(bban.dropFirst(4).prefix(6))
        let number = String(bban.dropFirst(10))
        return CzechBankAccount(prefix: prefix, number: number, bankCode: bankCode)
    }

    /// ISO 13616 check: move the first four characters to the end, map A–Z to 10–35, take modulo 97.
    static func mod97(_ text: String) -> Int {
        let rearranged = text.dropFirst(4) + text.prefix(4)
        var remainder = 0
        for character in rearranged {
            if let digit = character.wholeNumberValue, character.isASCII {
                remainder = (remainder * 10 + digit) % 97
            } else if let ascii = character.asciiValue, character.isLetter {
                let value = Int(ascii) - 55 // "A" (65) → 10
                remainder = (remainder * 100 + value) % 97
            } else {
                return -1
            }
        }
        return remainder
    }
}

extension IBAN: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let iban = IBAN(text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid IBAN: \(text)")
        }
        self = iban
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}
