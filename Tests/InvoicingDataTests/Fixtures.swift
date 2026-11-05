import Foundation
import InvoicingCore
@testable import InvoicingData

/// Fixtures for the data layer tests: the same supplier, customers and account as the core tests.
enum Fixtures {
    static func d(_ text: String) -> Decimal {
        guard let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) else { fatalError("Not a decimal literal: \(text)") }
        return value
    }

    static func day(_ iso: String) -> CalendarDay {
        guard let value = CalendarDay(iso: iso) else { fatalError("Not an ISO day: \(iso)") }
        return value
    }

    /// 2026-11-05T05:00:00Z.
    static let now = Date(timeIntervalSince1970: 1_793_854_800)

    static let supplier: Party = {
        guard let ico = IdentificationNumber("12345679"), let dic = VATIdentifier("CZ12345679") else { fatalError("bad supplier fixture") }
        // Typed as optional so the fixture compiles with the failable and the plain RegistryEntry initialiser.
        let registry: RegistryEntry? = RegistryEntry(court: .prague, section: "C", insert: "123456")
        return Party(name: "Nováková a synové s. r. o.",
                     address: PostalAddress(street: "Dlouhá 12", city: "Praha 1", postalCode: "110 00", countryCode: "CZ"),
                     identificationNumber: ico, vatIdentifier: dic, registryEntry: registry)
    }()

    static let czechParty: Party = {
        guard let ico = IdentificationNumber("25596641"), let dic = VATIdentifier("CZ25596641") else { fatalError("bad customer fixture") }
        return Party(name: "Odběratel s. r. o.", address: PostalAddress(street: "Krátká 1", city: "Brno", postalCode: "602 00"),
                     identificationNumber: ico, vatIdentifier: dic, email: "fakturace@odberatel.cz")
    }()

    static let germanParty: Party = {
        guard let vat = VATIdentifier("DE123456789") else { fatalError("bad customer fixture") }
        return Party(name: "Beispiel GmbH", address: PostalAddress(street: "Hauptstraße 1", city: "Berlin", postalCode: "10115", countryCode: "DE"),
                     vatIdentifier: vat)
    }()

    static let bank: BankConnection = {
        guard let account = CzechBankAccount(parsing: "19-2000145399/0800"), let bic = BIC("GIBACZPX"),
              let connection = BankConnection(czech: account, bic: bic, bankName: "Česká spořitelna", currency: nil) else {
            fatalError("bad bank fixture")
        }
        return connection
    }()

    static let profile = CompanyProfile(supplier: supplier, bankConnections: [bank], defaultCurrency: .czk, defaultPaymentTermDays: 14)

    static let eurRate = ExchangeRate(currency: .eur, amount: 1, czkPerAmount: d("24.310"), validFor: day("2026-11-04"), source: .cnb(order: 212))

    static func czechCustomer(id: String = "cust-cz") -> Customer {
        Customer(id: id, party: czechParty, currency: .czk, paymentTermDays: 14)
    }

    static func germanCustomer(id: String = "cust-de") -> Customer {
        Customer(id: id, party: germanParty, currency: .eur, paymentTermDays: 30)
    }

    /// A complete CZK draft: 10 h × 1 000 CZK at 21 % → 10 000 / 2 100 / 12 100.
    static func czkDraft(id: String = "doc-cz", customer: Customer = czechCustomer()) -> Document {
        Document(id: id, kind: .invoice, supplier: supplier, customer: customer.party, customerID: customer.id, language: .czech,
                 currency: .czk, pricing: .net, issueDate: day("2026-11-05"), taxPointDate: day("2026-11-04"), dueDate: day("2026-11-19"),
                 lines: [DocumentLine(id: "l1", text: "Konzultace – listopad 2026", quantity: 10, unit: "h", unitPrice: d("1000"), treatment: .taxable(.standard))])
    }

    /// A complete EUR reverse-charge draft with the ČNB rate: 1 000 EUR → 24 310 CZK base, no VAT.
    static func eurDraft(id: String = "doc-eu", customer: Customer = germanCustomer()) -> Document {
        Document(id: id, kind: .invoice, supplier: supplier, customer: customer.party, customerID: customer.id, language: .english,
                 currency: .eur, pricing: .net, issueDate: day("2026-11-05"), taxPointDate: day("2026-11-04"), dueDate: day("2026-12-05"),
                 lines: [DocumentLine(id: "l1", text: "Consulting – November 2026", quantity: 10, unit: "h", unitPrice: 100, treatment: .reverseChargeEU)],
                 exchangeRate: eurRate)
    }

    static func invoiceSeries(variableSymbolPrefix: String? = nil) throws -> StoredNumberSeries {
        StoredNumberSeries(name: "Faktury", kinds: [.invoice, .finalInvoice],
                           series: try DocumentNumberSeries(id: "fv", pattern: DocumentNumberPattern(template: "FV-{YYYY}-{NNN}"), year: 2026,
                                                            variableSymbolPrefix: variableSymbolPrefix))
    }

    /// A database with the profile, both customers and the invoice series.
    static func prepared() throws -> AppDatabase {
        let database = try AppDatabase()
        try ProfileStore(database).save(profile, now: now)
        try CustomerStore(database).save(czechCustomer(), now: now)
        try CustomerStore(database).save(germanCustomer(), now: now)
        try NumberSeriesStore(database).save(try invoiceSeries(), now: now)
        return database
    }

    /// Adds the advance request series "zf" (ZF-{YYYY}-{NNN}) and the payment tax document series "dd"
    /// (DD-{YYYY}-{NNN}).
    static func addAdvanceSeries(_ database: AppDatabase) throws {
        let store = NumberSeriesStore(database)
        try store.save(StoredNumberSeries(name: "Zálohové faktury", kinds: [.advanceRequest],
                                          series: try DocumentNumberSeries(id: "zf", pattern: DocumentNumberPattern(template: "ZF-{YYYY}-{NNN}"), year: 2026)),
                       now: now)
        try store.save(StoredNumberSeries(name: "Doklady k platbě", kinds: [.paymentTaxDocument],
                                          series: try DocumentNumberSeries(id: "dd", pattern: DocumentNumberPattern(template: "DD-{YYYY}-{NNN}"), year: 2026)),
                       now: now)
    }

    /// Saves and issues an advance request for 12 100 CZK from the "zf" series (see `addAdvanceSeries`).
    static func issuedAdvance(_ database: AppDatabase, id: String = "adv") throws -> Document {
        var request = czkDraft(id: id)
        request.kind = .advanceRequest
        request.taxPointDate = nil
        let store = DocumentStore(database)
        try store.saveDraft(request, now: now)
        return try store.issue(id: id, seriesID: "zf", now: now)
    }

    /// Records a payment of `amount` on the issued advance request, saves its payment tax document, links
    /// and issues it from the "dd" series (see `addAdvanceSeries`) and returns the issued receipt.
    static func issuedReceipt(_ database: AppDatabase, advance: Document, id: String = "dd1", amount: Decimal = d("12100"),
                              on day: CalendarDay = day("2026-11-10")) throws -> Document {
        let store = DocumentStore(database)
        let payment = try store.recordPayment(documentID: advance.id, on: day, amount: Money(amount, .czk), now: now)
        try store.saveDraft(Document.paymentTaxDocument(id: id, forAdvanceRequest: advance, received: amount, on: day), now: now)
        _ = try store.attachReceipt(paymentID: payment.id, documentID: id, now: now)
        return try store.issue(id: id, seriesID: "dd", now: now)
    }

    /// A final invoice draft for the supply of `czkDraft` (12 100 CZK gross) that deducts the issued
    /// payment tax document `receipt`.
    static func finalInvoiceDraft(id: String = "final", deducting receipt: Document) throws -> Document {
        var document = czkDraft(id: id)
        document.kind = .finalInvoice
        document.advanceDeductions = receipt.advanceDeductions(totals: try DocumentTotals.compute(for: receipt))
        return document
    }

    static let cnbDaily = """
    04.11.2026 #212
    země|měna|množství|kód|kurz
    EMU|euro|1|EUR|24,310
    USA|dolar|1|USD|21,123
    Japonsko|jen|100|JPY|13,845
    """
}
