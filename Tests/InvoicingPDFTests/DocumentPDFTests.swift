import AppKit
import Foundation
import PDFKit
import Testing
import Vision
import InvoicingCore
@testable import InvoicingPDF

/// The same supplier, customers and account as the core tests, plus one document of every kind.
enum PDFFixtures {
    static func d(_ text: String) -> Decimal {
        guard let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) else { fatalError("Not a decimal literal: \(text)") }
        return value
    }

    static func day(_ iso: String) -> CalendarDay {
        guard let value = CalendarDay(iso: iso) else { fatalError("Not an ISO day: \(iso)") }
        return value
    }

    static let supplier: Party = {
        guard let ico = IdentificationNumber("12345679"), let dic = VATIdentifier("CZ12345679") else { fatalError("bad supplier fixture") }
        let registry: RegistryEntry? = RegistryEntry(court: .prague, section: "C", insert: "123456")
        return Party(name: "Nováková a synové s. r. o.",
                     address: PostalAddress(street: "Dlouhá 12", city: "Praha 1", postalCode: "110 00", countryCode: "CZ"),
                     identificationNumber: ico, vatIdentifier: dic, registryEntry: registry, email: "fakturace@novakova.cz")
    }()

    static let germanCustomer: Party = {
        guard let vat = VATIdentifier("DE123456789") else { fatalError("bad customer fixture") }
        return Party(name: "Beispiel GmbH", address: PostalAddress(street: "Hauptstraße 1", city: "Berlin", postalCode: "10115", countryCode: "DE"),
                     vatIdentifier: vat)
    }()

    static let czechCustomer: Party = {
        guard let ico = IdentificationNumber("25596641"), let dic = VATIdentifier("CZ25596641") else { fatalError("bad customer fixture") }
        return Party(name: "Odběratel s. r. o.", address: PostalAddress(street: "Krátká 1", city: "Brno", postalCode: "602 00"),
                     identificationNumber: ico, vatIdentifier: dic)
    }()

    static let bank: BankConnection = {
        guard let account = CzechBankAccount(parsing: "19-2000145399/0800"), let bic = BIC("GIBACZPX"),
              let connection = BankConnection(czech: account, bic: bic, bankName: "Česká spořitelna", currency: nil) else {
            fatalError("bad bank fixture")
        }
        return connection
    }()

    static let eurRate = ExchangeRate(currency: .eur, amount: 1, czkPerAmount: d("24.310"), validFor: day("2026-11-04"), source: .cnb(order: 212))

    /// A domestic CZK invoice with two lines at 21 % and a discount, issued, with QR platba.
    static func czkInvoice() -> Document {
        Document(id: "doc-cz", kind: .invoice, status: .issued, number: "FV-2026-001", supplier: supplier, customer: czechCustomer,
                 language: .czech, currency: .czk, pricing: .net, issueDate: day("2026-11-05"), taxPointDate: day("2026-11-04"),
                 dueDate: day("2026-11-19"),
                 lines: [DocumentLine(id: "l1", text: "Konzultace – listopad 2026", quantity: 10, unit: "h", unitPrice: d("1000"), treatment: .taxable(.standard)),
                         DocumentLine(id: "l2", text: "Cestovní náklady", quantity: 1, unitPrice: d("500"), discountPercent: 10, treatment: .taxable(.standard))],
                 payment: PaymentInstructions.standard(for: "FV-2026-001", bankConnection: bank, currency: .czk, variableSymbolPrefix: "1"),
                 orderReference: "PO-4711", note: "Děkujeme za spolupráci.", footer: "Bankovní spojení viz výše.")
    }

    /// A reverse-charge EUR invoice to the German customer, bilingual, issued, with the EPC QR code.
    static func euInvoice() -> Document {
        Document(id: "doc-eu", kind: .invoice, status: .issued, number: "FV-2026-002", supplier: supplier, customer: germanCustomer,
                 language: .english, currency: .eur, pricing: .net, issueDate: day("2026-11-05"), taxPointDate: day("2026-11-04"),
                 dueDate: day("2026-11-19"),
                 lines: [DocumentLine(id: "l1", text: "Consulting – November 2026", quantity: 10, unit: "h", unitPrice: 100, treatment: .reverseChargeEU)],
                 exchangeRate: eurRate,
                 payment: PaymentInstructions.standard(for: "FV-2026-002", bankConnection: bank, currency: .eur, variableSymbolPrefix: "1"))
    }

    /// An EUR invoice with Czech VAT to a foreign customer: the VAT must also appear in CZK.
    static func euInvoiceWithCzechVAT() -> Document {
        var document = euInvoice()
        document.id = "doc-eu-vat"
        document.number = "FV-2026-003"
        document.lines = [DocumentLine(id: "l1", text: "Training in Prague", quantity: 2, unit: "days", unitPrice: 400, treatment: .taxable(.standard))]
        return document
    }

    static func advanceRequest() -> Document {
        Document(id: "adv", kind: .advanceRequest, status: .issued, number: "ZF-2026-001", supplier: supplier, customer: czechCustomer,
                 language: .czech, currency: .czk, pricing: .net, issueDate: day("2026-10-01"), dueDate: day("2026-10-15"),
                 lines: [DocumentLine(id: "l1", text: "Záloha na konzultace", quantity: 1, unitPrice: d("12100"), treatment: .taxable(.standard))],
                 payment: PaymentInstructions.standard(for: "ZF-2026-001", bankConnection: bank, currency: .czk, variableSymbolPrefix: "2"))
    }

    static func paymentTaxDocument() -> Document {
        var document = Document.paymentTaxDocument(id: "dd1", forAdvanceRequest: advanceRequest(), received: d("12100"), on: day("2026-10-10"),
                                                   issueDate: day("2026-10-12"))
        document.status = .issued
        document.number = "DD-2026-001"
        return document
    }

    static func finalInvoice() -> Document {
        Document(id: "fin", kind: .finalInvoice, status: .issued, number: "FV-2026-004", supplier: supplier, customer: czechCustomer,
                 language: .czech, currency: .czk, pricing: .net, issueDate: day("2026-11-05"), taxPointDate: day("2026-11-04"),
                 dueDate: day("2026-11-19"),
                 lines: [DocumentLine(id: "l1", text: "Konzultace – říjen a listopad 2026", quantity: 20, unit: "h", unitPrice: d("1000"), treatment: .taxable(.standard))],
                 advanceDeductions: [AdvanceDeduction(id: "ded1", documentNumber: "DD-2026-001", paymentDate: day("2026-10-10"), treatment: .taxable(.standard),
                                                      ratePercent: 21, base: d("10000"), vat: d("2100"), currency: .czk)],
                 payment: PaymentInstructions.standard(for: "FV-2026-004", bankConnection: bank, currency: .czk, variableSymbolPrefix: "1"),
                 relatedDocumentNumber: "ZF-2026-001")
    }

    /// A draft: no number, no payment instructions yet.
    static func draft() -> Document {
        var document = czkInvoice()
        document.id = "draft"
        document.status = .draft
        document.number = nil
        document.payment = nil
        return document
    }

    /// Sixty lines: more than one page.
    static func longInvoice() -> Document {
        var document = czkInvoice()
        document.id = "long"
        document.lines = (1...60).map {
            DocumentLine(id: "l\($0)", text: "Položka \($0) – delší popis položky, který se zalomí na dva řádky, aby se tabulka protáhla", quantity: Decimal($0),
                         unit: "ks", unitPrice: d("123.45"), treatment: .taxable(.standard))
        }
        return document
    }

    /// The CZK invoice from a supplier with a long business name and long street lines.
    static func longNamesInvoice() -> Document {
        var document = czkInvoice()
        document.id = "long-names"
        document.supplier.name = "Stavební a projekční společnost Novák a partneři, obchodní a poradenská skupina s. r. o."
        document.supplier.address = PostalAddress(street: "Na Příkopě 1234/56, budova C, vchod z Panské ulice, 5. patro, kancelář 512",
                                                  city: "Praha 1", postalCode: "110 00", countryCode: "CZ")
        document.customer.address = PostalAddress(street: "Krátká 1, areál Technologického parku, budova Jih, vrátnice 3",
                                                  city: "Brno", postalCode: "602 00")
        document.orderReference = "Objednávka zákazníka č. 2026/1145 pro projekt Praha Sever"
        guard let account = CzechBankAccount(parsing: "19-2000145399/0800"), let bic = BIC("GIBACZPX"),
              let connection = BankConnection(czech: account, bic: bic, bankName: "Československá obchodní banka, a. s., pobočka Praha 1 – Na Poříčí",
                                              currency: nil) else {
            fatalError("bad bank fixture")
        }
        document.payment?.bankConnection = connection
        return document
    }

    /// The final invoice in English: the longest bilingual totals captions.
    static func englishFinalInvoice() -> Document {
        var document = finalInvoice()
        document.id = "fin-en"
        document.language = .english
        return document
    }

    /// A supply at 21 % that deducts a larger advance taxed at the former reduced 15 %: a negative
    /// difference, taxed at the advance's rate (§ 37a odst. 2 písm. b) ZDPH).
    static func negativeDifferenceFinalInvoice() -> Document {
        var document = finalInvoice()
        document.id = "fin-neg"
        document.lines = [DocumentLine(id: "l1", text: "Konzultace", quantity: 1, unitPrice: d("1000"), treatment: .taxable(.standard))]
        document.advanceDeductions = [AdvanceDeduction(id: "ded1", documentNumber: "DD-2023-001", paymentDate: day("2023-10-10"),
                                                       treatment: .taxable(.reduced), ratePercent: 15, base: d("2000"), vat: d("300"), currency: .czk)]
        return document
    }

    /// Czech VAT and reverse charge on one document (the validator only warns).
    static func mixedTreatmentsInvoice() -> Document {
        var document = euInvoiceWithCzechVAT()
        document.id = "doc-mixed"
        document.lines.append(DocumentLine(id: "l2", text: "Consulting – November 2026", quantity: 10, unit: "h", unitPrice: 100, treatment: .reverseChargeEU))
        return document
    }

    static func everyKind() -> [Document] {
        [czkInvoice(), euInvoice(), euInvoiceWithCzechVAT(), advanceRequest(), paymentTaxDocument(), finalInvoice(), draft(), longInvoice()]
    }
}

enum PDFInspection {
    /// The text of the whole document with the non-breaking spaces of Czech formatting turned into spaces.
    static func text(_ pdf: PDFDocument) -> String {
        normalized(pdf.string ?? "")
    }

    static func normalized(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{00A0}", with: " ").replacingOccurrences(of: "\u{202F}", with: " ")
    }

    /// The words of `text`, for strings that may wrap (PDF text extraction can interleave wrapped lines
    /// with text of the other column at the same height).
    static func words(_ text: String) -> [String] {
        normalized(text).split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    /// The text at the height of every occurrence of `needle`, across the whole page width.
    static func linesContaining(_ needle: String, in pdf: PDFDocument) -> [String] {
        var lines: [String] = []
        for selection in pdf.findString(needle, withOptions: []) {
            guard let page = selection.pages.first else { continue }
            let bounds = selection.bounds(for: page)
            let pageBounds = page.bounds(for: .mediaBox)
            let rect = CGRect(x: pageBounds.minX, y: bounds.minY - 4, width: pageBounds.width, height: bounds.height + 8)
            lines.append(normalized(page.selection(for: rect)?.string ?? ""))
        }
        return lines
    }

    static func document(_ data: Data) throws -> PDFDocument {
        try #require(PDFDocument(data: data), "not a PDF")
    }

    /// Every QR code Vision finds on the rendered pages.
    static func qrPayloads(_ pdf: PDFDocument) throws -> [String] {
        var payloads: [String] = []
        for index in 0..<pdf.pageCount {
            guard let page = pdf.page(at: index) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let scale: CGFloat = 3
            let image = page.thumbnail(of: CGSize(width: bounds.width * scale, height: bounds.height * scale), for: .mediaBox)
            guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
            let request = VNDetectBarcodesRequest()
            request.symbologies = [.qr]
            try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
            for observation in request.results ?? [] {
                if let payload = observation.payloadStringValue { payloads.append(payload) }
            }
        }
        return payloads
    }
}

@Suite struct DocumentPDFTests {
    @Test func everyKindRendersAPDF() throws {
        for document in PDFFixtures.everyKind() {
            let data = try DocumentPDF.render(document)
            #expect(data.count > 1000, "\(document.id)")
            #expect(String(decoding: data.prefix(5), as: UTF8.self) == "%PDF-", "\(document.id)")
            let pdf = try PDFInspection.document(data)
            #expect(pdf.pageCount >= 1, "\(document.id)")
            #expect(!PDFInspection.text(pdf).isEmpty, "\(document.id)")
        }
    }

    @Test func aCzechInvoicePrintsTheMandatoryElements() throws {
        let document = PDFFixtures.czkInvoice()
        let text = PDFInspection.text(try PDFInspection.document(try DocumentPDF.render(document)))
        // § 29 odst. 1 ZDPH: the parties and their identifiers, the number, the dates, the base, the rate and the tax.
        for expected in ["Nováková a synové s. r. o.", "DIČ CZ12345679", "Odběratel s. r. o.", "DIČ CZ25596641", "FV-2026-001",
                         "Faktura – daňový doklad", "Datum vystavení", "5. 11. 2026", "Datum uskutečnění zdanitelného plnění", "4. 11. 2026",
                         "Datum splatnosti", "19. 11. 2026", "Sazba DPH", "21 %", "Základ daně", "10 450,00 Kč", "2 194,50 Kč", "12 644,50 Kč",
                         "Variabilní symbol", "12026001", "IBAN", "Objednávka", "PO-4711", "Děkujeme za spolupráci.", "Strana 1 / 1",
                         "Zapsána v obchodním rejstříku"] {
            #expect(text.contains(expected), "missing \(expected)")
        }
        #expect(!text.contains("KONCEPT"))
        #expect(!text.contains(" / Supplier"), "a Czech document carries no English gloss")
    }

    @Test func aReverseChargeInvoiceIsBilingualAndShowsNoVAT() throws {
        let document = PDFFixtures.euInvoice()
        let text = PDFInspection.text(try PDFInspection.document(try DocumentPDF.render(document)))
        for expected in ["Faktura – daňový doklad", "Invoice – tax document", "Odběratel / Customer", "Beispiel GmbH", "DIČ / VAT ID DE123456789",
                         "Daň odvede zákazník", "reverse charge", "1 000,00 €", "Germany", "Strana / Page 1 / 1",
                         "Registered in the Commercial Register"] {
            #expect(text.contains(expected), "missing \(expected)")
        }
        #expect(!text.contains("Sazba DPH"), "no VAT rate column without Czech VAT")
        #expect(!text.contains("Celkem bez DPH"), "no VAT total without Czech VAT")
    }

    @Test func aForeignCurrencyInvoiceWithCzechVATPrintsTheTaxInCZK() throws {
        let document = PDFFixtures.euInvoiceWithCzechVAT()
        let text = PDFInspection.text(try PDFInspection.document(try DocumentPDF.render(document)))
        // 800 € base, 168 € VAT; at 24,310: 19 448,00 Kč and 4 084,08 Kč (§ 29 odst. 1 písm. l) ZDPH).
        for expected in ["800,00 €", "168,00 €", "968,00 €", "19 448,00 Kč", "4 084,08 Kč", "24,310 CZK/EUR", "Přepočet na Kč", "Section 4(8)"] {
            #expect(text.contains(expected), "missing \(expected)")
        }
    }

    @Test func anAdvanceRequestSaysItIsNotATaxDocument() throws {
        let text = PDFInspection.text(try PDFInspection.document(try DocumentPDF.render(PDFFixtures.advanceRequest())))
        #expect(text.contains("Zálohová faktura"))
        #expect(text.contains("Toto není daňový doklad. Daňový doklad bude vystaven po přijetí platby."))
        #expect(!text.contains("Datum uskutečnění zdanitelného plnění"))
        #expect(text.contains("K úhradě"))
    }

    @Test func aPaymentTaxDocumentHasNoPaymentBlock() throws {
        let text = PDFInspection.text(try PDFInspection.document(try DocumentPDF.render(PDFFixtures.paymentTaxDocument())))
        #expect(text.contains("Daňový doklad k přijaté platbě"))
        #expect(text.contains("Datum přijetí platby"))
        #expect(text.contains("10. 10. 2026"))
        #expect(text.contains("Daňový doklad k platbě přijaté dne 10. 10. 2026 na základě zálohové faktury č. ZF-2026-001."))
        #expect(text.contains("Uhrazeno"))
        #expect(!text.contains("IBAN"))
        #expect(!text.contains("K úhradě"))
    }

    @Test func aFinalInvoiceListsTheDeductedAdvances() throws {
        let document = PDFFixtures.finalInvoice()
        let text = PDFInspection.text(try PDFInspection.document(try DocumentPDF.render(document)))
        // Supply 20 000 + 4 200 = 24 200; advance 10 000 + 2 100 = 12 100; due 12 100.
        for expected in ["Odečet záloh", "Odečet zálohy – daňový doklad č. DD-2026-001, platba ze dne 10. 10. 2026", "-12 100,00 Kč",
                         "Odečteny zálohy zdaněné daňovými doklady č. DD-2026-001", "20 000,00 Kč", "4 200,00 Kč", "24 200,00 Kč",
                         "10 000,00 Kč", "2 100,00 Kč", "12 100,00 Kč"] {
            #expect(text.contains(expected) || text.contains(expected.replacingOccurrences(of: "-", with: "−")), "missing \(expected)")
        }
        // The amount due, in the totals band and in the payment block, is the balance, not the supply.
        let dueLines = PDFInspection.linesContaining("K úhradě", in: try PDFInspection.document(try DocumentPDF.render(document)))
        #expect(!dueLines.isEmpty)
        for line in dueLines {
            #expect(line.contains("12 100,00 Kč"), "amount due line: \(line)")
            #expect(!line.contains("24 200,00 Kč"), "amount due line: \(line)")
        }
    }

    @Test func aNegativeDifferenceCaptionsTheSupplyAndTheDifferenceWithTheirOwnRates() throws {
        let document = PDFFixtures.negativeDifferenceFinalInvoice()
        let totals = try DocumentTotals.compute(for: document)
        let rows = DocumentPDFRenderer(document: document, totals: totals, totalPages: nil).summaryRows()
        let captions = rows.map(\.caption)
        #expect(captions.contains("Tuzemsko \(PDFFormat.percent(21)) – Plnění"), "\(captions)")
        #expect(captions.contains("Tuzemsko \(PDFFormat.percent(15)) – Základ daně a daň dokladu"), "\(captions)")
        #expect(!captions.contains("Tuzemsko \(PDFFormat.percent(15)) – Plnění"), "\(captions)")
        _ = try DocumentPDF.render(document)
    }

    @Test func rowsWithoutCzechVATPrintNoTaxInTheSummary() throws {
        let document = PDFFixtures.mixedTreatmentsInvoice()
        let totals = try DocumentTotals.compute(for: document)
        let rows = DocumentPDFRenderer(document: document, totals: totals, totalPages: nil).summaryRows()
        let reverseCharge = try #require(rows.first { $0.caption.hasPrefix("EU – přenesená daňová povinnost (PDP)") })
        #expect(reverseCharge.values.count == 3)
        #expect(reverseCharge.values[1] == nil, "no tax under reverse charge")
        #expect(reverseCharge.values[0] == 1000)
        let taxable = try #require(rows.first { $0.caption.hasPrefix("Tuzemsko") })
        #expect(taxable.values.compactMap { $0 } == [800, 168, 968])
        _ = try DocumentPDF.render(document)
    }

    @Test func aDraftCarriesTheThreeMarkersAndNoQRCode() throws {
        let data = try DocumentPDF.render(PDFFixtures.draft())
        let pdf = try PDFInspection.document(data)
        let text = PDFInspection.text(pdf)
        #expect(text.contains("KONCEPT / DRAFT"))
        #expect(text.contains("Číslo bude přiděleno při vystavení"))
        #expect(text.contains("QR po vystavení"))
        #expect(!text.contains("FV-2026-001"))
        #expect(try PDFInspection.qrPayloads(pdf).isEmpty)
    }

    @Test func theQRCodesDecodeToThePaymentStrings() throws {
        let czk = PDFFixtures.czkInvoice()
        let czkPDF = try PDFInspection.document(try DocumentPDF.render(czk))
        let czkPayloads = try PDFInspection.qrPayloads(czkPDF)
        let expectedCZK = try #require(czk.qrPlatba(totals: try DocumentTotals.compute(for: czk))).encoded()
        #expect(czkPayloads == [expectedCZK])

        let eur = PDFFixtures.euInvoice()
        let eurPDF = try PDFInspection.document(try DocumentPDF.render(eur))
        let eurPayloads = try PDFInspection.qrPayloads(eurPDF)
        #expect(eurPayloads.count == 1)
        let payload = eurPayloads.first ?? ""
        #expect(payload.hasPrefix("BCD\n002\n1\nSCT\n"))
        #expect(payload.contains(PDFFixtures.bank.iban.value))
        #expect(payload.contains("EUR1000.00"))
        #expect(PDFInspection.text(eurPDF).contains("EPC QR (SEPA)"))
        #expect(PDFInspection.text(czkPDF).contains("QR Platba"))

        // A final invoice asks for the balance after the advances, not the supply.
        let final = PDFFixtures.finalInvoice()
        let finalPayloads = try PDFInspection.qrPayloads(try PDFInspection.document(try DocumentPDF.render(final)))
        let expectedFinal = try #require(final.qrPlatba(totals: try DocumentTotals.compute(for: final))).encoded()
        #expect(finalPayloads == [expectedFinal])
        #expect(expectedFinal.contains("AM:12100.00"))
    }

    @Test func anIssuedDocumentWhoseQRCodeCannotBeEncodedSaysSoInItsPlace() throws {
        var document = PDFFixtures.euInvoice()
        // More than the 70 characters the EPC name field takes.
        document.supplier.name = "Nováková a synové, stavební, projekční a poradenská společnost s. r. o."
        let pdf = try PDFInspection.document(try DocumentPDF.render(document))
        let text = PDFInspection.text(pdf)
        // The notice wraps inside the 85 pt box, so the words are compared, not the lines.
        #expect(PDFInspection.words(text).joined(separator: " ").contains("QR kód není k dispozici / QR code unavailable"),
                "the notice stands where the code would be")
        #expect(!text.contains("EPC QR (SEPA)"), "no caption without a code")
        #expect(try PDFInspection.qrPayloads(pdf).isEmpty, "no code is drawn")
        #expect(text.contains("IBAN"), "the payment details still let the customer pay")
        // The draft shows the placeholder and renders.
        document.status = .draft
        document.number = nil
        let draft = PDFInspection.text(try PDFInspection.document(try DocumentPDF.render(document)))
        #expect(PDFInspection.words(draft).joined(separator: " ").contains("QR po vystavení / QR after issue"))
        #expect(!draft.contains("QR code unavailable"))
    }

    @Test func largeAmountsShrinkInsteadOfBeingCut() throws {
        var document = PDFFixtures.finalInvoice()
        document.id = "fin-big"
        document.lines = [DocumentLine(id: "l1", text: "Stavba haly – konečné vyúčtování", quantity: 1, unit: "ks",
                                       unitPrice: PDFFixtures.d("3000000"), treatment: .taxable(.standard))]
        document.advanceDeductions = [AdvanceDeduction(id: "ded1", documentNumber: "DD-2026-007", paymentDate: PDFFixtures.day("2026-10-10"),
                                                       treatment: .taxable(.standard), ratePercent: 21,
                                                       base: PDFFixtures.d("2000000"), vat: PDFFixtures.d("420000"), currency: .czk)]
        let text = PDFInspection.text(try PDFInspection.document(try DocumentPDF.render(document)))
        #expect(!text.contains("…"), "no amount is cut")
        // Supply 3 000 000 + 630 000; advance 2 000 000 + 420 000; due 1 210 000.
        for expected in ["3 000 000,00 Kč", "630 000,00 Kč", "-2 000 000,00 Kč", "-420 000,00 Kč", "1 210 000,00 Kč",
                         "Odečet zálohy – daňový doklad č. DD-2026-007, platba ze dne 10. 10. 2026, sazba DPH 21 %"] {
            #expect(text.contains(expected) || text.contains(expected.replacingOccurrences(of: "-", with: "−")), "missing \(expected)")
        }
    }

    @Test func aLongDocumentPaginatesWithRunningHeadersAndPageNumbers() throws {
        let pdf = try PDFInspection.document(try DocumentPDF.render(PDFFixtures.longInvoice()))
        #expect(pdf.pageCount >= 2)
        let pages = pdf.pageCount
        for index in 0..<pages {
            let text = PDFInspection.normalized(pdf.page(at: index)?.string ?? "")
            #expect(text.contains("Strana \(index + 1) / \(pages)"), "page \(index + 1)")
            if index > 0 {
                #expect(text.contains("(pokračování)"), "page \(index + 1)")
                // The table header repeats on every page that continues the lines; the payment block may
                // take the last page alone.
                if text.contains("Položka ") {
                    #expect(text.contains("Popis"), "the table header repeats on page \(index + 1)")
                }
            }
        }
        let text = PDFInspection.text(pdf)
        #expect(text.contains("Položka 1 –"))
        #expect(text.contains("Položka 60 –"))
        #expect(text.contains("K úhradě"))
    }

    @Test func theLinesTableFitsTheContentWidth() throws {
        let contentWidth = DocumentPDF.pageSize.width - 2 * DocumentPDFRenderer.horizontalMargin
        for document in PDFFixtures.everyKind() + [PDFFixtures.longNamesInvoice(), PDFFixtures.mixedTreatmentsInvoice()] {
            let columns = DocumentPDFRenderer.tableColumns(for: document, contentWidth: contentWidth)
            let description = try #require(columns.first)
            #expect(description.key == .description)
            #expect(description.width >= DocumentPDFRenderer.minimumDescriptionWidth, "\(document.id)")
            var x: CGFloat = 0
            for column in columns {
                #expect(x + column.width <= contentWidth + 0.01, "\(document.id): \(column.key) ends at \(x + column.width)")
                x += column.width + DocumentPDFRenderer.gap
            }
        }
        // The CZK invoice has a unit and a discount: the unit joins the quantity, the per-line VAT goes.
        let keys = DocumentPDFRenderer.tableColumns(for: PDFFixtures.czkInvoice(), contentWidth: contentWidth).map(\.key)
        #expect(keys == [.description, .quantity, .unitPrice, .discount, .rate, .base, .total])

        // On the page: the first line's total (10 h × 1 000 Kč + 21 %) ends inside the right margin.
        let pdf = try PDFInspection.document(try DocumentPDF.render(PDFFixtures.czkInvoice()))
        let needle = PDFFormat.money(PDFFixtures.d("12100"), .czk)
        let selections = pdf.findString(needle, withOptions: []) + pdf.findString(PDFInspection.normalized(needle), withOptions: [])
        #expect(!selections.isEmpty)
        let contentRight = DocumentPDF.pageSize.width - DocumentPDFRenderer.horizontalMargin
        for selection in selections {
            guard let page = selection.pages.first else { continue }
            #expect(selection.bounds(for: page).maxX <= contentRight + 1, "line total at \(selection.bounds(for: page))")
        }
        #expect(PDFInspection.text(pdf).contains("10 h"), "the unit is printed with the quantity")
    }

    @Test func longNamesAndValuesWrapInsteadOfBeingCut() throws {
        let document = PDFFixtures.longNamesInvoice()
        let text = PDFInspection.text(try PDFInspection.document(try DocumentPDF.render(document)))
        #expect(!text.contains("…"), "nothing is truncated")
        for value in [document.supplier.name, document.supplier.address.street, document.customer.address.street,
                      document.orderReference ?? "", document.payment?.bankConnection.bankName ?? ""] {
            for word in PDFInspection.words(value) {
                #expect(text.contains(word), "missing \(word) of \(value)")
            }
        }
        // What follows the wrapped name is still there.
        #expect(text.contains("IČO 12345679"))
        #expect(text.contains("fakturace@novakova.cz"))
        #expect(text.contains("Zapsána v obchodním rejstříku"))
    }

    @Test func englishTotalsCaptionsAreNotCut() throws {
        for document in [PDFFixtures.euInvoiceWithCzechVAT(), PDFFixtures.englishFinalInvoice()] {
            let text = PDFInspection.text(try PDFInspection.document(try DocumentPDF.render(document)))
            #expect(!text.contains("…"), "\(document.id): nothing is truncated")
            for word in ["Total", "excl.", "VAT", "Amount", "due"] {
                #expect(text.contains(word), "\(document.id): missing \(word)")
            }
        }
        let text = PDFInspection.text(try PDFInspection.document(try DocumentPDF.render(PDFFixtures.englishFinalInvoice())))
        for word in ["Less", "advance", "payments"] {
            #expect(text.contains(word), "missing \(word)")
        }
    }

    @Test func identifiersAreGlossedOnBilingualDocuments() throws {
        let english = PDFInspection.text(try PDFInspection.document(try DocumentPDF.render(PDFFixtures.euInvoice())))
        #expect(english.contains("IČO / Company ID (IČO) 12345679"))
        #expect(english.contains("DIČ / VAT ID CZ12345679"))
        let czech = PDFInspection.text(try PDFInspection.document(try DocumentPDF.render(PDFFixtures.czkInvoice())))
        #expect(czech.contains("IČO 12345679"))
        #expect(czech.contains("DIČ CZ12345679"))
        #expect(!czech.contains("Company ID"))
    }

    @Test func grossPricesAreCaptionedAsIncludingVAT() throws {
        let document = PDFFixtures.paymentTaxDocument()
        #expect(document.pricing == .gross)
        let text = PDFInspection.text(try PDFInspection.document(try DocumentPDF.render(document)))
        #expect(text.contains("Cena za MJ s DPH"))
        #expect(!text.contains("…"))
        let net = PDFInspection.text(try PDFInspection.document(try DocumentPDF.render(PDFFixtures.czkInvoice())))
        #expect(!net.contains("Cena za MJ s DPH"))
    }

    @Test func renderingIsDeterministicForTheSameDocument() throws {
        let document = PDFFixtures.czkInvoice()
        let first = try DocumentPDF.render(document)
        let second = try DocumentPDF.render(document)
        // Core Graphics stamps the creation date into the PDF, so compare the extracted text and the size.
        #expect(first.count == second.count)
        #expect(PDFInspection.text(try PDFInspection.document(first)) == PDFInspection.text(try PDFInspection.document(second)))
    }

    @Test func fileNamesAreSafe() {
        #expect(DocumentPDF.fileName(for: PDFFixtures.euInvoice()) == "FV-2026-002 Beispiel GmbH.pdf")
        #expect(DocumentPDF.fileName(for: PDFFixtures.draft()) == "Koncept Odběratel s. r. o.pdf")
        var document = PDFFixtures.czkInvoice()
        document.number = "FV/2026/001"
        document.customer.name = "A: B\\C  D"
        #expect(DocumentPDF.fileName(for: document) == "FV-2026-001 A- B-C D.pdf")
    }
}
