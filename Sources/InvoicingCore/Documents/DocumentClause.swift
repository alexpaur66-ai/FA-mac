/// A legal or explanatory sentence printed on a document, in the document's language.
public enum DocumentClause: Hashable, Sendable {
    /// "Daň odvede zákazník" (§ 29 odst. 2 písm. c) ZDPH); the Czech wording is prescribed, so it stays
    /// on English documents too.
    case reverseCharge
    /// Reference to the provision the supply is exempt under (§ 29 odst. 2 písm. a) ZDPH).
    case exempt(reference: String)
    /// A service with the place of supply outside the Czech Republic (§ 9 odst. 1 ZDPH); informative.
    case outsideScope
    /// Printed on every advance request.
    case notATaxDocument
    /// The opening sentence of a payment tax document.
    case paymentReceived(on: CalendarDay, advanceNumber: String?)
    /// The advances a final invoice deducts (§ 37a ZDPH).
    case advancesDeducted(documentNumbers: [String])
    /// The rate behind the CZK amounts (§ 4 odst. 8 ZDPH).
    case exchangeRate(ExchangeRate)

    public func text(language: DocumentLanguage) -> String {
        switch (self, language) {
        case (.reverseCharge, .czech):
            return "Daň odvede zákazník."
        case (.reverseCharge, .english):
            return "Daň odvede zákazník – reverse charge: the VAT is to be accounted for by the customer (Article 196 of Council Directive 2006/112/EC)."
        case (.exempt(let reference), .czech):
            return "Osvobozeno od daně podle \(reference) zákona č. 235/2004 Sb., o dani z přidané hodnoty."
        case (.exempt(let reference), .english):
            return "Exempt from VAT under \(reference) of Act No. 235/2004 Coll., on Value Added Tax."
        case (.outsideScope, .czech):
            return "Plnění není předmětem daně v tuzemsku – místo plnění je mimo tuzemsko (§ 9 odst. 1 zákona o DPH)."
        case (.outsideScope, .english):
            return "Not subject to Czech VAT – the place of supply is outside the Czech Republic (Section 9(1) of the Czech VAT Act)."
        case (.notATaxDocument, .czech):
            return "Toto není daňový doklad. Daňový doklad bude vystaven po přijetí platby."
        case (.notATaxDocument, .english):
            return "This is not a tax document. A tax document will be issued upon receipt of the payment."
        case (.paymentReceived(let day, let advanceNumber), .czech):
            let reference = advanceNumber.map { " na základě zálohové faktury č. \($0)" } ?? ""
            return "Daňový doklad k platbě přijaté dne \(day.czechString)\(reference)."
        case (.paymentReceived(let day, let advanceNumber), .english):
            let reference = advanceNumber.map { " against advance invoice No. \($0)" } ?? ""
            return "Tax document for the payment received on \(Self.english(day))\(reference)."
        case (.advancesDeducted(let numbers), .czech):
            return "Odečteny zálohy zdaněné daňovými doklady č. \(numbers.joined(separator: ", ")) (§ 37a zákona o DPH)."
        case (.advancesDeducted(let numbers), .english):
            return "Less the advance payments taxed on tax documents No. \(numbers.joined(separator: ", ")) (Section 37a of the Czech VAT Act)."
        case (.exchangeRate(let rate), .czech):
            return "Přepočet na Kč \(Self.czechSource(rate)) \(rate.czechLabel) ze dne \(rate.validFor.czechString) (§ 4 odst. 8 zákona o DPH)."
        case (.exchangeRate(let rate), .english):
            return "Amounts in CZK converted at the \(Self.englishSource(rate)) \(rate.czechLabel) of \(Self.english(rate.validFor)) (Section 4(8) of the Czech VAT Act)."
        }
    }

    /// The clauses a document prints, derived from its kind, lines, deductions and exchange rate.
    public static func clauses(for document: Document) -> [DocumentClause] {
        var result: [DocumentClause] = []
        if !document.kind.isTaxDocument {
            result.append(.notATaxDocument)
        }
        if document.kind == .paymentTaxDocument, let day = document.taxPointDate {
            result.append(.paymentReceived(on: day, advanceNumber: document.relatedDocumentNumber))
        }
        for treatment in document.treatments {
            switch treatment {
            case .reverseChargeEU: result.append(.reverseCharge)
            case .exempt(let reference): result.append(.exempt(reference: reference))
            case .outsideEU: result.append(.outsideScope)
            case .taxable: break
            }
        }
        if document.kind.deductsAdvances, !document.advanceDeductions.isEmpty {
            var numbers: [String] = []
            for deduction in document.advanceDeductions where !numbers.contains(deduction.documentNumber) {
                numbers.append(deduction.documentNumber)
            }
            result.append(.advancesDeducted(documentNumbers: numbers))
        }
        if document.kind.isTaxDocument, document.currency != .czk, let rate = document.exchangeRate {
            result.append(.exchangeRate(rate))
        }
        return result
    }

    private static let englishMonths = ["January", "February", "March", "April", "May", "June", "July", "August",
                                        "September", "October", "November", "December"]

    /// "4 November 2026"; `CalendarDay` guarantees the month is 1...12.
    static func english(_ day: CalendarDay) -> String {
        "\(day.day) \(englishMonths[day.month - 1]) \(day.year)"
    }

    private static func czechSource(_ rate: ExchangeRate) -> String {
        switch rate.source {
        case .cnb: return "kurzem ČNB"
        case .ecb: return "kurzem ECB"
        case .manual, .fixedAccounting: return "kurzem"
        }
    }

    private static func englishSource(_ rate: ExchangeRate) -> String {
        switch rate.source {
        case .cnb: return "CNB exchange rate"
        case .ecb: return "ECB exchange rate"
        case .manual, .fixedAccounting: return "exchange rate"
        }
    }
}
