/// The commercial-register entry a Czech company must state on its documents (§ 435 odst. 1 of the
/// Civil Code): the register and the court that keeps it, with section (oddíl) and insert (vložka).
public struct RegistryEntry: Hashable, Sendable, Codable {
    public var court: RegistryCourt
    /// "C" for an s.r.o., "B" for an a.s., "A" for partnerships and others.
    public var section: String
    /// The insert number, e.g. "123456".
    public var insert: String

    public init(court: RegistryCourt, section: String, insert: String) {
        self.court = court
        self.section = section.trimmingWhitespace().uppercased()
        self.insert = insert.trimmingWhitespace()
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
