/// How VAT applies to a supply on a document.
public enum VATTreatment: Hashable, Sendable, Codable {
    /// Czech VAT at the given rate; the tax amount is shown on the document in CZK (§ 29 odst. 1 písm. l) ZDPH).
    case taxable(VATRateKind)
    /// Service for a VAT-registered business in another EU member state, place of supply there
    /// (§ 9 odst. 1 ZDPH). No Czech VAT; the document carries „daň odvede zákazník“ (§ 29 odst. 2 písm. c))
    /// and the customer's VAT ID; the supply goes into the souhrnné hlášení (§ 102 odst. 1 písm. d)).
    case reverseChargeEU
    /// Service for a business outside the EU, place of supply outside the EU (§ 9 odst. 1 ZDPH):
    /// not subject to Czech VAT. No rate, no tax, no reverse-charge clause.
    case outsideEU
    /// Exempt supply; `reference` is the provision the document must cite (§ 29 odst. 2 písm. a) ZDPH).
    case exempt(reference: String)

    /// True when Czech VAT is charged and must be shown.
    public var chargesVAT: Bool {
        if case .taxable = self { return true }
        return false
    }

    /// True when the customer's VAT ID is mandatory on the document.
    public var requiresCustomerVATID: Bool { self == .reverseChargeEU }

    /// True when the supply is reported in the souhrnné hlášení (§ 102 ZDPH).
    public var reportedInECSalesList: Bool { self == .reverseChargeEU }

    /// A stable key for grouping lines in the VAT summary.
    public var groupingKey: String {
        switch self {
        case .taxable(let kind): return "taxable:\(kind.rawValue)"
        case .reverseChargeEU: return "reverseChargeEU"
        case .outsideEU: return "outsideEU"
        case .exempt(let reference): return "exempt:\(reference)"
        }
    }
}
