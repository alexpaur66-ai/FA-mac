import Foundation

/// A document in its own currency: who, what, when and how to pay. Amounts are computed by
/// `DocumentTotals`, the rules are checked by `DocumentValidator`, the printed legal texts come from
/// `DocumentClause`. The supplier and customer are snapshots, so the document stays as issued when the
/// company profile or the customer card change later (§ 35 ZDPH).
public struct Document: Hashable, Sendable, Codable, Identifiable {
    public var id: String
    public var kind: DocumentKind
    public var status: DocumentStatus
    /// Evidenční číslo (§ 29 odst. 1 písm. e) ZDPH); nil until the document is issued.
    public var number: String?
    public var supplier: Party
    public var customer: Party
    /// Id of the customer record the document belongs to, when any.
    public var customerID: String?
    public var language: DocumentLanguage
    public var currency: Currency
    public var pricing: PricingMode
    /// Datum vystavení (§ 29 odst. 1 písm. g) ZDPH).
    public var issueDate: CalendarDay
    /// Datum uskutečnění zdanitelného plnění for an invoice, the day the payment was received for a payment
    /// tax document (§ 29 odst. 1 písm. h) ZDPH); nil on an advance request.
    public var taxPointDate: CalendarDay?
    public var dueDate: CalendarDay
    public var lines: [DocumentLine]
    /// Advances deducted on a final invoice (§ 37a ZDPH); empty on every other kind.
    public var advanceDeductions: [AdvanceDeduction]
    /// Advances paid on § 64 goods, which have no payment tax document, listed on a final invoice as paid in
    /// advance (ADR 0012); they reduce only the amount due. Nil or empty on every other kind; nil on
    /// documents saved before the field existed.
    public var paidAdvances: [PaidAdvance]?
    /// The rate behind the CZK amounts (§ 4 odst. 8, § 29 odst. 1 písm. l) ZDPH); nil on CZK documents.
    public var exchangeRate: ExchangeRate?
    public var payment: PaymentInstructions?
    /// Number of the advance request a payment tax document settles.
    public var relatedDocumentNumber: String?
    /// The customer's order or contract reference.
    public var orderReference: String?
    public var note: String?
    public var footer: String?

    public init(id: String = UUID().uuidString, kind: DocumentKind, status: DocumentStatus = .draft, number: String? = nil,
                supplier: Party, customer: Party, customerID: String? = nil, language: DocumentLanguage = .czech,
                currency: Currency = .czk, pricing: PricingMode = .net, issueDate: CalendarDay, taxPointDate: CalendarDay? = nil,
                dueDate: CalendarDay, lines: [DocumentLine] = [], advanceDeductions: [AdvanceDeduction] = [],
                paidAdvances: [PaidAdvance]? = nil, exchangeRate: ExchangeRate? = nil, payment: PaymentInstructions? = nil, relatedDocumentNumber: String? = nil,
                orderReference: String? = nil, note: String? = nil, footer: String? = nil) {
        self.id = id
        self.kind = kind
        self.status = status
        self.number = number
        self.supplier = supplier
        self.customer = customer
        self.customerID = customerID
        self.language = language
        self.currency = currency
        self.pricing = pricing
        self.issueDate = issueDate
        self.taxPointDate = taxPointDate
        self.dueDate = dueDate
        self.lines = lines
        self.advanceDeductions = advanceDeductions
        self.paidAdvances = paidAdvances
        self.exchangeRate = exchangeRate
        self.payment = payment
        self.relatedDocumentNumber = relatedDocumentNumber
        self.orderReference = orderReference
        self.note = note
        self.footer = footer
    }

    /// The day the obligation to declare the tax arose: the tax point, or the issue date when none is set.
    /// A document of goods exempt under § 64 declares the supply on the § 22 odst. 1 day instead
    /// (`exchangeRateDay`).
    public var taxPoint: CalendarDay { taxPointDate ?? issueDate }

    public var isTaxDocument: Bool { kind.isTaxDocument }

    /// The distinct VAT treatments of the lines, in order of first appearance.
    public var treatments: [VATTreatment] {
        var seen: [VATTreatment] = []
        for line in lines where !seen.contains(line.treatment) {
            seen.append(line.treatment)
        }
        return seen
    }

    /// True when any line is a reverse-charge supply (§ 29 odst. 2 písm. c) ZDPH).
    public var hasReverseCharge: Bool { lines.contains { $0.treatment == .reverseChargeEU } }

    /// True when any line is goods supplied to another member state exempt under § 64 ZDPH.
    public var hasIntraCommunityGoods: Bool { lines.contains { $0.treatment == .intraCommunityGoods } }

    /// True when any line needs the customer's VAT ID from another member state (reverse charge, § 64).
    public var requiresCustomerVATID: Bool { lines.contains { $0.treatment.requiresCustomerVATID } }

    /// True when the document has lines and every one is goods supplied to another member state under
    /// § 64 ZDPH: an advance request like that needs no payment tax document for the money received (ADR 0012).
    public var isIntraCommunityGoodsOnly: Bool {
        !lines.isEmpty && lines.allSatisfy { $0.treatment == .intraCommunityGoods }
    }

    /// The day whose exchange rate converts the document to CZK: the day the obligation to declare the tax
    /// or the supply arose (§ 4 odst. 8 ZDPH). That is the tax point, except on a document whose lines are
    /// all goods exempt under § 64: their supply is declared on the § 22 odst. 1 day (`ReportingDay`), the
    /// 15th of the month after the supply or the earlier issue date. A document that mixes them with other
    /// treatments and a payment tax document keep the tax point (ACCT, ADR 0011).
    public var exchangeRateDay: CalendarDay {
        guard kind != .paymentTaxDocument, isIntraCommunityGoodsOnly else { return taxPoint }
        return ReportingDay.day(treatment: .intraCommunityGoods, taxPoint: taxPoint, issueDate: issueDate)
    }

    /// The day that puts the document in a month of the accountant's export (screens-flows.md §2h, ACCT): an
    /// advance request, which is not a tax document, by its issue date; a document whose lines are all goods
    /// exempt under § 64 by the § 22 odst. 1 day (`ReportingDay`); every other tax document, a mixed one and a
    /// payment tax document included, by its DUZP. The Issue sheet's check for an exported month uses it too.
    public var exportDay: CalendarDay {
        switch kind {
        case .advanceRequest:
            return issueDate
        case .paymentTaxDocument:
            return taxPoint
        case .invoice, .finalInvoice:
            guard isIntraCommunityGoodsOnly else { return taxPoint }
            return ReportingDay.day(treatment: .intraCommunityGoods, taxPoint: taxPoint, issueDate: issueDate)
        }
    }

    /// The heading in the document's language.
    public var title: String { kind.title(language: language) }
}
