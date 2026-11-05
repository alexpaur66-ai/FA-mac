import Foundation

extension Document {
    /// The QR platba string of this document, or nil when it has no payment instructions asking for a
    /// Czech QR code, no number, or nothing to pay. Encode it with `QRPlatba.encoded()`. The recipient name
    /// (RN) and the message (MSG) are optional in the format, so they are shortened to fit its limits
    /// (35 and 60 characters after encoding, with the default folding) instead of making the encoding fail.
    public func qrPlatba(totals: DocumentTotals) -> QRPlatba? {
        guard let payment, payment.qrCode == .qrPlatba, let number, totals.amountDue > 0 else { return nil }
        var code = QRPlatba(
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
        let fold = code.foldsTextToQRAlphanumeric
        code.message = code.message.map { Self.fitted($0, key: "MSG", fold: fold) }
        code.recipientName = code.recipientName.map { Self.fitted($0, key: "RN", fold: fold) }
        return code
    }

    /// `text` without trailing characters until its QR platba encoding fits the field's maximum length.
    /// Characters are dropped before encoding, so a percent escape is never cut in half.
    private static func fitted(_ text: String, key: String, fold: Bool) -> String {
        guard let maximum = QRPlatba.maximumLengths[key] else { return text }
        var candidate = text
        while !candidate.isEmpty && QRPlatba.encodeText(candidate, fold: fold).count > maximum {
            candidate.removeLast()
        }
        return candidate
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
    /// ZDPH), with the day of receipt as its tax point. The received amount is split across the request's
    /// VAT treatments in proportion to their gross amounts on the request, one gross line per treatment
    /// (§ 37: the tax on a payment follows the rate of the supply it pays for); each share is rounded to
    /// the currency's minor units and the last one takes the remainder, so the lines add up to `amount`.
    /// A request with one treatment gives one line. The caller may edit the lines when the customer
    /// designated the payment differently, numbers the document and adds the exchange rate for foreign
    /// currencies. `amount` must be positive; the validator refuses a receipt of zero or less.
    public static func paymentTaxDocument(id: String = UUID().uuidString, forAdvanceRequest request: Document,
                                          received amount: Decimal, on paymentDate: CalendarDay,
                                          issueDate: CalendarDay? = nil) -> Document {
        let text: String
        switch request.language {
        case .czech:
            text = "Přijatá platba" + (request.number.map { " k zálohové faktuře č. \($0)" } ?? "")
        case .english:
            text = "Payment received" + (request.number.map { " against advance invoice No. \($0)" } ?? "")
        }
        let lines = receiptLines(for: request, amount: amount, text: text)
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
            lines: lines,
            relatedDocumentNumber: request.number,
            orderReference: request.orderReference
        )
    }

    /// The gross lines of a payment tax document for `amount` received against `request`: one per VAT
    /// treatment of the request, the amount split in proportion to the treatments' gross on the request.
    private static func receiptLines(for request: Document, amount: Decimal, text: String) -> [DocumentLine] {
        let fallback = request.lines.first?.treatment ?? .taxable(.standard)
        let single = [DocumentLine(text: text, quantity: 1, unitPrice: amount, treatment: fallback)]
        // The request's own summary rows, so the split follows what the customer was asked to pay.
        guard let totals = try? DocumentTotals.compute(for: request) else { return single }
        let rows = totals.rows.filter { $0.gross != 0 }
        let requestGross = rows.reduce(Decimal(0)) { $0 + $1.gross }
        guard requestGross > 0, let first = rows.first else { return single }
        guard rows.count > 1 else {
            return [DocumentLine(text: text, quantity: 1, unitPrice: amount, treatment: first.treatment)]
        }
        let scale = request.currency.minorUnits
        var allocated = Decimal(0)
        var lines: [DocumentLine] = []
        for (index, row) in rows.enumerated() {
            let share: Decimal
            if index == rows.count - 1 {
                share = amount - allocated
            } else {
                share = (amount * row.gross / requestGross).rounded(scale: scale)
                allocated += share
            }
            let lineText = text + " (" + treatmentNote(row.treatment, rate: row.rate, language: request.language) + ")"
            lines.append(DocumentLine(text: lineText, quantity: 1, unitPrice: share, treatment: row.treatment))
        }
        return lines
    }

    /// "DPH 21 %", "VAT 12 %", "reverse charge" …: which part of a split payment a line is.
    private static func treatmentNote(_ treatment: VATTreatment, rate: VATRate?, language: DocumentLanguage) -> String {
        switch (treatment, language) {
        case (.taxable, .czech):
            return "DPH " + (rate.map { $0.percent.plainString } ?? "") + " %"
        case (.taxable, .english):
            return "VAT " + (rate.map { $0.percent.plainString } ?? "") + " %"
        case (.intraCommunityGoods, .czech):
            return "dodání zboží do jiného členského státu"
        case (.intraCommunityGoods, .english):
            return "intra-Community supply of goods"
        case (.reverseChargeEU, .czech):
            return "přenesení daňové povinnosti"
        case (.reverseChargeEU, .english):
            return "reverse charge"
        case (.outsideEU, .czech):
            return "mimo předmět daně v tuzemsku"
        case (.outsideEU, .english):
            return "outside the scope of Czech VAT"
        case (.exempt, .czech):
            return "osvobozeno"
        case (.exempt, .english):
            return "exempt"
        }
    }

    /// The deductions a final invoice takes from this payment tax document: one per VAT summary row, in
    /// this document's currency, carrying the rate and the exchange rate the advance was taxed at
    /// (§ 37a odst. 2 písm. b) ZDPH). Empty for any other kind or an unnumbered document.
    public func advanceDeductions(totals: DocumentTotals) -> [AdvanceDeduction] {
        guard kind == .paymentTaxDocument, let number else { return [] }
        return totals.rows.map { row in
            AdvanceDeduction(documentNumber: number, paymentDate: taxPoint, treatment: row.treatment,
                             ratePercent: row.appliedRatePercent ?? row.rate?.percent, base: row.taxableBase,
                             vat: row.taxableVAT, currency: currency, exchangeRate: totals.exchangeRate)
        }
    }
}
