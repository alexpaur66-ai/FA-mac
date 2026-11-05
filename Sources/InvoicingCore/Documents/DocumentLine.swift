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
    /// Base and VAT of the advance, in the final invoice's currency.
    public var base: Decimal
    public var vat: Decimal

    public init(id: String = UUID().uuidString, documentNumber: String, paymentDate: CalendarDay, treatment: VATTreatment,
                ratePercent: Decimal?, base: Decimal, vat: Decimal) {
        self.id = id
        self.documentNumber = documentNumber
        self.paymentDate = paymentDate
        self.treatment = treatment
        self.ratePercent = ratePercent
        self.base = base
        self.vat = vat
    }

    public var gross: Decimal { base + vat }
}
