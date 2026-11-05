/// A legal or natural person named on a document: the supplier or the customer.
public struct Party: Hashable, Sendable, Codable {
    /// Business name including the legal form, e.g. "Nováková a synové s. r. o." (§ 29 odst. 1 písm. a) ZDPH).
    public var name: String
    public var address: PostalAddress
    /// IČO; Czech companies must print it (§ 435 Civil Code).
    public var identificationNumber: IdentificationNumber?
    /// DIČ or foreign VAT ID (§ 29 odst. 1 písm. b) and d) ZDPH).
    public var vatIdentifier: VATIdentifier?
    /// Commercial-register entry; Czech companies must print it (§ 435 Civil Code).
    public var registryEntry: RegistryEntry?
    public var email: String?
    public var phone: String?

    public init(name: String, address: PostalAddress, identificationNumber: IdentificationNumber? = nil,
                vatIdentifier: VATIdentifier? = nil, registryEntry: RegistryEntry? = nil, email: String? = nil, phone: String? = nil) {
        self.name = name.trimmingWhitespace()
        self.address = address
        self.identificationNumber = identificationNumber
        self.vatIdentifier = vatIdentifier
        self.registryEntry = registryEntry
        self.email = email
        self.phone = phone
    }
}

/// How VAT applies to a customer, which decides the default treatment of the lines on their documents.
/// The defaults follow the place-of-supply rule for general services (§ 9 ZDPH): business customers
/// are taxed where they are established, consumers where the supplier is. Goods and the special
/// services of § 10–10i differ; the user can override the treatment on each line.
public enum CustomerVATStatus: String, Sendable, Codable, CaseIterable {
    /// Czech company or person registered for VAT: Czech VAT is charged.
    case czechVATPayer
    /// Czech customer without VAT registration: Czech VAT is charged all the same.
    case czechNonPayer
    /// Business in another EU member state with a VAT ID: reverse charge, the customer accounts for VAT.
    case euBusiness
    /// Consumer in another EU member state: Czech VAT is charged (general services, § 9 odst. 2).
    case euConsumer
    /// Business outside the EU: the service is outside the scope of Czech VAT (§ 9 odst. 1).
    case nonEUBusiness
    /// Consumer outside the EU: Czech VAT is charged by the general rule; § 10h may move the place of
    /// supply abroad for consulting, advertising and similar services, which is the accountant's call.
    case nonEUConsumer

    public var defaultServiceTreatment: VATTreatment {
        switch self {
        case .czechVATPayer, .czechNonPayer, .euConsumer, .nonEUConsumer: return .taxable(.standard)
        case .euBusiness: return .reverseChargeEU
        case .nonEUBusiness: return .outsideEU
        }
    }

    /// True when the document must carry the customer's VAT ID (§ 29 odst. 1 písm. d) ZDPH).
    public var requiresVATIdentifier: Bool { self == .czechVATPayer || self == .euBusiness }

    /// The status implied by a VAT identifier and the country of the customer's seat; a customer with no
    /// identifier is a consumer or a non-payer by country.
    public static func inferred(vatIdentifier: VATIdentifier?, countryCode: String) -> CustomerVATStatus {
        let country = countryCode.uppercased()
        if let vatIdentifier {
            if vatIdentifier.isCzech { return .czechVATPayer }
            return vatIdentifier.isEU ? .euBusiness : .nonEUBusiness
        }
        if country == "CZ" { return .czechNonPayer }
        return VATIdentifier.euPrefixes.contains(country == "GR" ? "EL" : country) ? .euConsumer : .nonEUConsumer
    }
}

/// A customer in the light CRM: the party plus how they are invoiced.
public struct Customer: Hashable, Sendable, Codable, Identifiable {
    public var id: String
    public var party: Party
    public var vatStatus: CustomerVATStatus
    /// Currency their documents are issued in.
    public var currency: Currency
    /// Days from the issue date to the due date.
    public var paymentTermDays: Int
    public var language: DocumentLanguage
    public var notes: String

    public init(id: String, party: Party, vatStatus: CustomerVATStatus? = nil, currency: Currency = .czk,
                paymentTermDays: Int = 14, language: DocumentLanguage? = nil, notes: String = "") {
        self.id = id
        self.party = party
        self.vatStatus = vatStatus ?? CustomerVATStatus.inferred(vatIdentifier: party.vatIdentifier, countryCode: party.address.countryCode)
        self.currency = currency
        self.paymentTermDays = paymentTermDays
        self.language = language ?? (party.address.isCzech ? .czech : .english)
        self.notes = notes
    }
}
