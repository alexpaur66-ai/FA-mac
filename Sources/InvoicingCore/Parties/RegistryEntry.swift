/// The commercial-register entry a Czech company must state on its documents (§ 435 odst. 1 of the
/// Civil Code): the register and the court that keeps it, with section (oddíl) and insert (vložka).
public struct RegistryEntry: Hashable, Sendable {
    public var court: RegistryCourt
    /// "C" for an s.r.o., "B" for an a.s., "A" for partnerships, "Dr" for cooperatives, "Pr" for
    /// contributory organisations; stored with its first letter capitalised, the rest as entered.
    public var section: String
    /// The insert number, e.g. "123456".
    public var insert: String

    /// Nil when the section or the insert is empty after trimming: § 435 odst. 1 of the Civil Code
    /// requires both, and the register sentence would otherwise print "vložka .".
    public init?(court: RegistryCourt, section: String, insert: String) {
        let section = Self.normalizeSection(section)
        let insert = insert.trimmingWhitespace()
        guard !section.isEmpty, !insert.isEmpty else { return nil }
        self.court = court
        self.section = section
        self.insert = insert
    }

    /// Trims and capitalises the first letter only: "c" becomes "C", "Dr" stays "Dr" (the register writes
    /// two-letter sections in mixed case), "dr" becomes "Dr".
    static func normalizeSection(_ raw: String) -> String {
        let trimmed = raw.trimmingWhitespace()
        guard let first = trimmed.first else { return trimmed }
        return String(first).uppercased() + trimmed.dropFirst()
    }

    /// "Zapsána v obchodním rejstříku vedeném Městským soudem v Praze, oddíl C, vložka 123456."
    /// "Registered in the Commercial Register kept by the Municipal Court in Prague, Section C, Insert 123456."
    public func sentence(language: DocumentLanguage) -> String {
        switch language {
        case .czech:
            return "Zapsána v obchodním rejstříku vedeném \(court.czechInstrumental), oddíl \(section), vložka \(insert)."
        case .english:
            return "Registered in the Commercial Register kept by the \(court.english), Section \(section), Insert \(insert)."
        }
    }
}

extension RegistryEntry: Codable {
    private enum CodingKeys: String, CodingKey {
        case court, section, insert
    }

    /// Decodes through the checking initialiser, so stored data with an empty section or insert fails.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let court = try container.decode(RegistryCourt.self, forKey: .court)
        let section = try container.decode(String.self, forKey: .section)
        let insert = try container.decode(String.self, forKey: .insert)
        guard let entry = RegistryEntry(court: court, section: section, insert: insert) else {
            throw DecodingError.dataCorruptedError(forKey: .insert, in: container,
                                                   debugDescription: "Registry entry needs a section and an insert")
        }
        self = entry
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(court, forKey: .court)
        try container.encode(section, forKey: .section)
        try container.encode(insert, forKey: .insert)
    }
}

/// The seven Czech courts that keep the commercial register, with the grammatical forms the
/// register sentence needs.
public enum RegistryCourt: String, Sendable, Codable, CaseIterable {
    case prague, ceskeBudejovice, plzen, ustiNadLabem, hradecKralove, brno, ostrava

    /// Nominative, as the court names itself: "Městský soud v Praze".
    public var czechNominative: String {
        switch self {
        case .prague: return "Městský soud v Praze"
        case .ceskeBudejovice: return "Krajský soud v Českých Budějovicích"
        case .plzen: return "Krajský soud v Plzni"
        case .ustiNadLabem: return "Krajský soud v Ústí nad Labem"
        case .hradecKralove: return "Krajský soud v Hradci Králové"
        case .brno: return "Krajský soud v Brně"
        case .ostrava: return "Krajský soud v Ostravě"
        }
    }

    /// Instrumental, as used after "vedeném": "Městským soudem v Praze".
    public var czechInstrumental: String {
        switch self {
        case .prague: return "Městským soudem v Praze"
        case .ceskeBudejovice: return "Krajským soudem v Českých Budějovicích"
        case .plzen: return "Krajským soudem v Plzni"
        case .ustiNadLabem: return "Krajským soudem v Ústí nad Labem"
        case .hradecKralove: return "Krajským soudem v Hradci Králové"
        case .brno: return "Krajským soudem v Brně"
        case .ostrava: return "Krajským soudem v Ostravě"
        }
    }

    public var english: String {
        switch self {
        case .prague: return "Municipal Court in Prague"
        case .ceskeBudejovice: return "Regional Court in České Budějovice"
        case .plzen: return "Regional Court in Plzeň"
        case .ustiNadLabem: return "Regional Court in Ústí nad Labem"
        case .hradecKralove: return "Regional Court in Hradec Králové"
        case .brno: return "Regional Court in Brno"
        case .ostrava: return "Regional Court in Ostrava"
        }
    }
}
