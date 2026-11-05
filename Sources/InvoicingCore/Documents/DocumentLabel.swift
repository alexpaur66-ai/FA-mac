/// Field captions printed on documents, in Czech and English.
public enum DocumentLabel: String, Sendable, CaseIterable {
    case documentNumber, issueDate, taxPointDate, paymentReceivedDate, dueDate
    case supplier, customer, identificationNumber, vatIdentifier, orderReference
    case description, quantity, unit, unitPrice, discount, base, vatRate, vat, total
    case vatSummary, advanceDeductions, amountDue, alreadyPaid
    case paymentDetails, bankAccount, iban, bic, variableSymbol, constantSymbol, specificSymbol, paymentReference
    case exchangeRate, inCZK, page, note

    public func text(language: DocumentLanguage) -> String {
        let texts = Self.texts(for: self)
        return language == .czech ? texts.cs : texts.en
    }

    private static func texts(for label: DocumentLabel) -> (cs: String, en: String) {
        switch label {
        case .documentNumber: return ("Číslo dokladu", "Document No.")
        case .issueDate: return ("Datum vystavení", "Date of issue")
        case .taxPointDate: return ("Datum uskutečnění zdanitelného plnění", "Date of taxable supply")
        case .paymentReceivedDate: return ("Datum přijetí platby", "Date of payment receipt")
        case .dueDate: return ("Datum splatnosti", "Due date")
        case .supplier: return ("Dodavatel", "Supplier")
        case .customer: return ("Odběratel", "Customer")
        case .identificationNumber: return ("IČO", "Company ID (IČO)")
        case .vatIdentifier: return ("DIČ", "VAT ID")
        case .orderReference: return ("Objednávka", "Order reference")
        case .description: return ("Popis", "Description")
        case .quantity: return ("Množství", "Quantity")
        case .unit: return ("MJ", "Unit")
        case .unitPrice: return ("Cena za MJ", "Unit price")
        case .discount: return ("Sleva", "Discount")
        case .base: return ("Základ daně", "Tax base")
        case .vatRate: return ("Sazba DPH", "VAT rate")
        case .vat: return ("DPH", "VAT")
        case .total: return ("Celkem", "Total")
        case .vatSummary: return ("Rekapitulace DPH", "VAT summary")
        case .advanceDeductions: return ("Odečet záloh", "Less advance payments")
        case .amountDue: return ("K úhradě", "Amount due")
        case .alreadyPaid: return ("Uhrazeno", "Paid")
        case .paymentDetails: return ("Platební údaje", "Payment details")
        case .bankAccount: return ("Číslo účtu", "Account number")
        case .iban: return ("IBAN", "IBAN")
        case .bic: return ("BIC/SWIFT", "BIC/SWIFT")
        case .variableSymbol: return ("Variabilní symbol", "Variable symbol")
        case .constantSymbol: return ("Konstantní symbol", "Constant symbol")
        case .specificSymbol: return ("Specifický symbol", "Specific symbol")
        case .paymentReference: return ("Platební reference", "Payment reference")
        case .exchangeRate: return ("Kurz", "Exchange rate")
        case .inCZK: return ("v Kč", "in CZK")
        case .page: return ("Strana", "Page")
        case .note: return ("Poznámka", "Note")
        }
    }
}
