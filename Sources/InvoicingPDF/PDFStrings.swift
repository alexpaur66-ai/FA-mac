import Foundation
import InvoicingCore

/// Texts printed on documents that are neither legal wording (`DocumentClause`) nor field captions
/// (`DocumentLabel`): the draft markers, the VAT summary row labels and the QR captions. Wording marked
/// ACCT follows the design system's legal-strings table and waits for the accountant's confirmation.
enum PDFStrings {
    /// Czech first, the English gloss after a slash on bilingual documents (design-system.md §9).
    static func bilingual(_ czech: String, _ english: String, _ language: DocumentLanguage) -> String {
        language == .english ? "\(czech) / \(english)" : czech
    }

    static func label(_ label: DocumentLabel, _ language: DocumentLanguage) -> String {
        bilingual(label.text(language: .czech), label.text(language: .english), language)
    }

    /// Drawn across every page of a draft (screens-flows.md §2c), always in both languages.
    static let watermark = "KONCEPT / DRAFT"

    static func numberPlaceholder(_ language: DocumentLanguage) -> String {
        bilingual("Číslo bude přiděleno při vystavení", "number assigned at issue", language)
    }

    static func qrPlaceholder(_ language: DocumentLanguage) -> String {
        bilingual("QR po vystavení", "QR after issue", language)
    }

    static func continued(_ language: DocumentLanguage) -> String {
        bilingual("pokračování", "continued", language)
    }

    /// The label of a VAT summary row (ACCT: "Tuzemsko 21 % · EU – přenesená daňová povinnost (PDP) ·
    /// Mimo EU · Osvobozeno").
    static func treatment(_ treatment: VATTreatment, percent: Decimal?, _ language: DocumentLanguage) -> String {
        switch treatment {
        case .taxable:
            let rate = percent.map { PDFFormat.percent($0) } ?? ""
            return bilingual("Tuzemsko \(rate)", "Czech VAT \(rate)", language)
        case .reverseChargeEU:
            return bilingual("EU – přenesená daňová povinnost (PDP)", "reverse charge", language)
        case .outsideEU:
            return bilingual("Mimo EU", "outside the EU", language)
        case .exempt:
            return bilingual("Osvobozeno", "exempt", language)
        }
    }

    /// The short rate cell of a line that does not carry Czech VAT.
    static func rateCell(_ treatment: VATTreatment) -> String {
        switch treatment {
        case .taxable: return ""
        case .reverseChargeEU: return "PDP"
        case .outsideEU, .exempt: return "—"
        }
    }

    /// Sub-rows of a VAT summary row on a final invoice: the supply, the advances and the difference.
    static func supplyRow(_ language: DocumentLanguage) -> String { bilingual("Plnění", "supply", language) }
    static func afterDeduction(_ language: DocumentLanguage) -> String {
        bilingual("Základ daně a daň dokladu", "tax base and VAT of this document", language)
    }

    /// "Odečet zálohy – daňový doklad č. DD-2026-001, platba ze dne 10. 10. 2026" (ACCT).
    static func deductionLine(number: String, paymentDate: CalendarDay, _ language: DocumentLanguage) -> String {
        let czech = "Odečet zálohy – daňový doklad č. \(number), platba ze dne \(PDFFormat.day(paymentDate))"
        guard language == .english else { return czech }
        return czech + " / advance payment deducted – tax document No. \(number), paid on \(PDFFormat.day(paymentDate))"
    }

    static func totalExcludingVAT(_ language: DocumentLanguage) -> String {
        bilingual("Celkem bez DPH", "Total excl. VAT", language)
    }

    static func inCZKAtRate(_ rate: ExchangeRate, _ language: DocumentLanguage) -> String {
        bilingual("v Kč, kurz \(rate.czechLabel)", "in CZK at \(rate.czechLabel)", language)
    }

    static func qrCaption(_ kind: PaymentQRKind) -> String {
        switch kind {
        case .qrPlatba: return "QR Platba"
        case .sepa: return "SEPA QR (EPC)"
        case .none: return ""
        }
    }

    static func bankName(_ language: DocumentLanguage) -> String { bilingual("Banka", "Bank", language) }
}
