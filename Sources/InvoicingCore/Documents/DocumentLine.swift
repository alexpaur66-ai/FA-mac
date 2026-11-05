import Foundation

/// One line of a document as the user enters it: the scope and subject of the supply, quantity, unit
/// price without VAT and discount (§ 29 odst. 1 písm. f) and i) ZDPH).
public struct DocumentLine: Hashable, Sendable, Codable, Identifiable {
    public var id: String
    /// What is supplied, e.g. "Konzultace – listopad 2026".
    public var text: String
    public var quantity: Decimal
    /// Unit of the quantity, e.g. "hod", "ks", "měsíc"; nil when the line has no natural unit.
    public var unit: String?
    /// Price per unit, net or gross according to the document's `PricingMode`.
    public var unitPrice: Decimal
    /// 0...100, a discount on the line total, shown on the document.
    public var discountPercent: Decimal
    public var treatment: VATTreatment

    public init(id: String = UUID().uuidString, text: String, quantity: Decimal = 1, unit: String? = nil,
                unitPrice: Decimal, discountPercent: Decimal = 0, treatment: VATTreatment) {
        self.id = id
        self.text = text
        self.quantity = quantity
        self.unit = unit
        self.unitPrice = unitPrice
        self.discountPercent = discountPercent
        self.treatment = treatment
    }

    /// The calculator's view of the line.
    public var input: LineInput {
        LineInput(quantity: quantity, unitPrice: unitPrice, discountPercent: discountPercent, treatment: treatment)
    }
}

/// An advance already taxed on a payment tax document and deducted on the final invoice (§ 37a ZDPH).
public struct AdvanceDeduction: Hashable, Sendable, Codable, Identifiable {
    public var id: String
    /// Number of the payment tax document the advance was taxed on.
    public var documentNumber: String
    /// The day the advance was received: the tax point of that payment tax document.
    public var paymentDate: CalendarDay
    public var treatment: VATTreatment
    /// The VAT percentage applied when the advance was taxed; it is the rate of a negative difference
    /// (§ 37a odst. 2 písm. b) ZDPH). Nil for treatments without Czech VAT.
    public var ratePercent: Decimal?
    /// Base and VAT of the advance in `currency`, which must be the final invoice's currency (nil: legacy
    /// data, assumed to match). The validator refuses a deduction in another currency.
    public var base: Decimal
    public var vat: Decimal
    /// The currency of the payment tax document the advance was taxed on; nil for data stored before the
    /// field existed.
    public var currency: Currency?
    /// The exchange rate the payment tax document converted the advance to CZK with; it is the rate of a
    /// negative difference (§ 37a odst. 2 písm. b) ZDPH). Nil on CZK documents and for data stored before
    /// the field existed, in which case the final invoice falls back to its own rate and warns.
    public var exchangeRate: ExchangeRate?

    public init(id: String = UUID().uuidString, documentNumber: String, paymentDate: CalendarDay, treatment: VATTreatment,
                ratePercent: Decimal?, base: Decimal, vat: Decimal, currency: Currency? = nil, exchangeRate: ExchangeRate? = nil) {
        self.id = id
        self.documentNumber = documentNumber
        self.paymentDate = paymentDate
        self.treatment = treatment
        self.ratePercent = ratePercent
        self.base = base
        self.vat = vat
        self.currency = currency
        self.exchangeRate = exchangeRate
    }

    public var gross: Decimal { base + vat }
}

/// An advance paid on goods supplied to another member state under § 64 ZDPH, listed on the final invoice
/// as paid in advance (ADR 0012). Such an advance has no payment tax document: § 20a odst. 2 and
/// § 28 odst. 1 písm. d) ZDPH concern taxable supplies, and an exempt supply is not one (§ 2 odst. 2 ZDPH).
/// It reduces only what the customer still pays; the value of the supply, and so the tax base, stays whole.
public struct PaidAdvance: Hashable, Sendable, Codable, Identifiable {
    public var id: String
    /// Number of the advance request the money was paid on.
    public var advanceNumber: String
    /// The day the payment was received.
    public var paidOn: CalendarDay
    /// The amount received, in `currency`, which must be the final invoice's currency.
    public var amount: Decimal
    public var currency: Currency
    /// The stored payment this row settles; nil for an advance the app does not know (paid before it).
    public var paymentID: String?
    /// The treatment of the advance request's lines: `.intraCommunityGoods` when all of them are § 64 goods,
    /// otherwise the first other one; nil when unknown. Anything but § 64 goods is a point for the
    /// accountant, since such an advance may have needed a payment tax document.
    public var advanceTreatment: VATTreatment?

    public init(id: String = UUID().uuidString, advanceNumber: String, paidOn: CalendarDay, amount: Decimal, currency: Currency,
                paymentID: String? = nil, advanceTreatment: VATTreatment? = nil) {
        self.id = id
        self.advanceNumber = advanceNumber
        self.paidOn = paidOn
        self.amount = amount
        self.currency = currency
        self.paymentID = paymentID
        self.advanceTreatment = advanceTreatment
    }

    /// The `advanceTreatment` of a document with these lines.
    public static func treatment(of lines: [DocumentLine]) -> VATTreatment? {
        guard !lines.isEmpty else { return nil }
        return lines.first { $0.treatment != .intraCommunityGoods }?.treatment ?? .intraCommunityGoods
    }
}
