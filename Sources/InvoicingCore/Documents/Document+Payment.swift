import Foundation

extension Document {
    /// The QR platba string of this document, or nil when it has no payment instructions asking for a
    /// Czech QR code, no number, or nothing to pay. Encode it with `QRPlatba.encoded()`.
    public func qrPlatba(totals: DocumentTotals) -> QRPlatba? {
        guard let payment, payment.qrCode == .qrPlatba, let number, totals.amountDue > 0 else { return nil }
        return QRPlatba(
            iban: payment.bankConnection.iban,
            bic: payment.bankConnection.bic,
            amount: totals.amountDue.rounded(scale: currency.minorUnits),
            currency: currency,
            dueDate: dueDate,
            variableSymbol: payment.variableSymbol,
            specificSymbol: payment.specificSymbol,
            constantSymbol: payment.constantSymbol,
            message: payment.message ?? number,
            recipientName: supplier.name
        )
    }

    /// The EPC QR payload of this document: EUR documents with payment instructions asking for a SEPA
    /// code, a number and an amount to pay. Encode it with `SEPAQRCode.encoded()`.
    public func sepaQRCode(totals: DocumentTotals) -> SEPAQRCode? {
        guard let payment, payment.qrCode == .sepa, let number, currency == .eur, totals.amountDue > 0 else { return nil }
        return SEPAQRCode(
            bic: payment.bankConnection.bic,
            name: supplier.name,
            iban: payment.bankConnection.iban,
            amount: totals.amountDue.rounded(scale: currency.minorUnits),
            creditorReference: payment.creditorReference,
            remittanceText: payment.creditorReference == nil ? (payment.message ?? number) : nil
        )
    }

    /// The tax document for a payment received against an advance request (§ 20a odst. 2, § 28 odst. 1
    /// ZDPH): one gross line for the received amount, taxed like the request's first line, with the day of
    /// receipt as its tax point. The caller numbers it and adds the exchange rate for foreign currencies.
    public static func paymentTaxDocument(id: String = UUID().uuidString, forAdvanceRequest request: Document,
                                          received amount: Decimal, on paymentDate: CalendarDay,
                                          issueDate: CalendarDay? = nil) -> Document {
        let treatment = request.lines.first?.treatment ?? .taxable(.standard)
        let text: String
        switch request.language {
        case .czech:
            text = "Přijatá platba" + (request.number.map { " k zálohové faktuře č. \($0)" } ?? "")
        case .english:
            text = "Payment received" + (request.number.map { " against advance invoice No. \($0)" } ?? "")
        }
        let issued = issueDate ?? paymentDate
        return Document(
            id: id,
            kind: .paymentTaxDocument,
            supplier: request.supplier,
            customer: request.customer,
            customerID: request.customerID,
            language: request.language,
            currency: request.currency,
            pricing: .gross,
            issueDate: issued,
            taxPointDate: paymentDate,
            dueDate: issued,
            lines: [DocumentLine(text: text, quantity: 1, unitPrice: amount, treatment: treatment)],
            relatedDocumentNumber: request.number,
            orderReference: request.orderReference
        )
    }

    /// The deductions a final invoice takes from this payment tax document: one per VAT summary row,
    /// carrying the rate the advance was taxed at (§ 37a ZDPH). Empty for any other kind or an unnumbered document.
    public func advanceDeductions(totals: DocumentTotals) -> [AdvanceDeduction] {
        guard kind == .paymentTaxDocument, let number else { return [] }
        return totals.rows.map { row in
            AdvanceDeduction(documentNumber: number, paymentDate: taxPoint, treatment: row.treatment,
                             ratePercent: row.rate?.percent, base: row.taxableBase, vat: row.taxableVAT)
        }
    }
}
