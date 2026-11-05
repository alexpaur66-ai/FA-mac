/// How VAT applies to a supply on a document.
public enum VATTreatment: Hashable, Sendable, Codable {
    /// Czech VAT at the given rate; the tax amount is shown on the document in CZK (§ 29 odst. 1 písm. l) ZDPH).
    case taxable(VATRateKind)
    /// Goods dispatched or transported from the Czech Republic to a business registered for VAT in another
    /// EU member state (§ 64 odst. 1 ZDPH): exempt with the right to deduct, provided the customer gave
    /// their VAT ID (písm. a)), the goods leave for that state (písm. b)) and the supply is reported in the
    /// souhrnné hlášení (písm. c), § 102 odst. 1 písm. a)). The document cites the exemption (§ 29 odst. 2
    /// písm. a)) and carries no rate or tax (§ 29 odst. 3 písm. e) bod 1). It is due 15 days after the end
    /// of the month of supply (§ 28 odst. 9 písm. a)) and declared on the day `ReportingDay` gives (§ 22).
    case intraCommunityGoods
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

    /// True when the customer's VAT ID from another member state is mandatory: the reverse charge needs it
    /// on the document (§ 29 odst. 1 písm. d)), the § 64 exemption needs it to apply at all (§ 64 odst. 1
    /// písm. a)).
    public var requiresCustomerVATID: Bool { self == .reverseChargeEU || self == .intraCommunityGoods }

    /// True when the supply is reported in the souhrnné hlášení (§ 102 odst. 1 písm. a) and d) ZDPH).
    public var reportedInECSalesList: Bool { self == .reverseChargeEU || self == .intraCommunityGoods }

    /// A stable key for grouping lines in the VAT summary.
    public var groupingKey: String {
        switch self {
        case .taxable(let kind): return "taxable:\(kind.rawValue)"
        case .intraCommunityGoods: return "intraCommunityGoods"
        case .reverseChargeEU: return "reverseChargeEU"
        case .outsideEU: return "outsideEU"
        case .exempt(let reference): return "exempt:\(reference)"
        }
    }
}
