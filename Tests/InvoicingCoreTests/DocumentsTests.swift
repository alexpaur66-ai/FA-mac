import Foundation
import Testing
@testable import InvoicingCore

/// Shared fixtures: a Czech supplier, a German business customer, a Czech customer and the supplier's account.
/// IČO check digits were recomputed in Python; the IBAN is the verified vector from BankingTests.
enum DocumentFixtures {
    static let supplier: Party = {
        guard let ico = IdentificationNumber("12345679"), let dic = VATIdentifier("CZ12345679") else { fatalError("bad supplier fixture") }
        return Party(name: "Nováková a synové s. r. o.",
                     address: PostalAddress(street: "Dlouhá 12", city: "Praha 1", postalCode: "110 00", countryCode: "CZ"),
                     identificationNumber: ico, vatIdentifier: dic,
                     registryEntry: RegistryEntry(court: .prague, section: "C", insert: "123456"))
    }()

    static let germanCustomer: Party = {
        guard let vat = VATIdentifier("DE123456789") else { fatalError("bad customer fixture") }
        return Party(name: "Beispiel GmbH",
                     address: PostalAddress(street: "Hauptstraße 1", city: "Berlin", postalCode: "10115", countryCode: "DE"),
                     vatIdentifier: vat)
    }()

    static let czechCustomer: Party = {
        guard let ico = IdentificationNumber("25596641"), let dic = VATIdentifier("CZ25596641") else { fatalError("bad customer fixture") }
        return Party(name: "Odběratel s. r. o.",
                     address: PostalAddress(street: "Krátká 1", city: "Brno", postalCode: "602 00"),
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

    /// A reverse-charge invoice in EUR to the German customer: 10 hours at 100 EUR.
    static func euInvoice() -> Document {
        Document(id: "doc-eu", kind: .invoice, status: .issued, number: "FV-2026-001", supplier: supplier, customer: germanCustomer,
                 language: .english, currency: .eur, pricing: .net, issueDate: day("2026-11-05"), taxPointDate: day("2026-11-04"),
                 dueDate: day("2026-11-19"),
                 lines: [DocumentLine(id: "l1", text: "Consulting – November 2026", quantity: 10, unit: "h", unitPrice: 100, treatment: .reverseChargeEU)],
                 exchangeRate: eurRate,
                 payment: PaymentInstructions.standard(for: "FV-2026-001", bankConnection: bank, currency: .eur))
    }

    /// A domestic CZK invoice: three lines of 0.35 CZK at 21 %, the § 37 rounding example of ADR 0002.
    static func czkInvoice() -> Document {
        Document(id: "doc-cz", kind: .invoice, status: .issued, number: "FV-2026-001", supplier: supplier, customer: czechCustomer,
                 language: .czech, currency: .czk, pricing: .net, issueDate: day("2026-11-05"), taxPointDate: day("2026-11-04"),
                 dueDate: day("2026-11-19"),
                 lines: (1...3).map { DocumentLine(id: "l\($0)", text: "Položka \($0)", quantity: 1, unitPrice: d("0.35"), treatment: .taxable(.standard)) },
                 payment: PaymentInstructions.standard(for: "FV-2026-001", bankConnection: bank, currency: .czk))
    }
}

@Suite struct DocumentKindTests {
    @Test func taxDocumentFlagsAndTitles() {
        #expect(!DocumentKind.advanceRequest.isTaxDocument)
        #expect(DocumentKind.invoice.isTaxDocument)
        #expect(DocumentKind.paymentTaxDocument.isTaxDocument)
        #expect(DocumentKind.finalInvoice.isTaxDocument)
        #expect(DocumentKind.finalInvoice.deductsAdvances)
        #expect(!DocumentKind.invoice.deductsAdvances)
        #expect(DocumentKind.invoice.title(language: .czech) == "Faktura – daňový doklad")
        #expect(DocumentKind.paymentTaxDocument.title(language: .english) == "Tax document for received payment")
        for kind in DocumentKind.allCases {
            for language in DocumentLanguage.allCases {
                #expect(!kind.title(language: language).isEmpty)
            }
        }
    }
}

@Suite struct DocumentTotalsTests {
    @Test func reverseChargeInvoiceInEUR() throws {
        let document = DocumentFixtures.euInvoice()
        let totals = try DocumentTotals.compute(for: document)
        #expect(totals.rows.count == 1)
        let row = try #require(totals.rows.first)
        #expect(row.treatment == .reverseChargeEU)
        #expect(row.rate == nil)
        #expect(row.base == 1000)
        #expect(row.vat == 0)
        #expect(row.gross == 1000)
        #expect(row.taxableBase == 1000)
        #expect(row.taxableVAT == 0)
        #expect(row.taxableBaseCZK == d("24310.00"))
        #expect(row.taxableVATCZK == 0)
        #expect(totals.amountDue == 1000)
        #expect(totals.taxableBaseCZK == d("24310.00"))
        #expect(totals.taxableVATCZK == 0)
        #expect(totals.amountDueMoney == Money(1000, .eur))
        #expect(totals.exchangeRate == DocumentFixtures.eurRate)
    }

    @Test func domesticInvoiceInCZK() throws {
        let totals = try DocumentTotals.compute(for: DocumentFixtures.czkInvoice())
        #expect(totals.totalBase == d("1.05"))
        #expect(totals.totalVAT == d("0.22"))
        #expect(totals.totalGross == d("1.27"))
        #expect(totals.amountDue == d("1.27"))
        #expect(totals.taxableVATCZK == d("0.22"))
        #expect(totals.taxableBaseCZK == d("1.05"))
        #expect(totals.exchangeRate == nil)
        #expect(totals.lines.count == 3)
        #expect(totals.deductedBase == 0)
    }

    @Test func finalInvoiceDeductsAdvances() throws {
        var document = DocumentFixtures.czkInvoice()
        document.kind = .finalInvoice
        document.lines = [DocumentLine(id: "l1", text: "Dodávka", quantity: 1, unitPrice: 1000, treatment: .taxable(.standard))]
        document.advanceDeductions = [
            AdvanceDeduction(documentNumber: "DD-2026-001", paymentDate: day("2026-10-01"), treatment: .taxable(.standard), ratePercent: 21, base: 400, vat: 84),
        ]
        let totals = try DocumentTotals.compute(for: document)
        let row = try #require(totals.rows.first)
        #expect(row.base == 1000)
        #expect(row.vat == 210)
        #expect(row.deductedBase == 400)
        #expect(row.deductedVAT == 84)
        #expect(row.taxableBase == 600)
        #expect(row.taxableVAT == 126)
        #expect(totals.deductedBase == 400)
        #expect(totals.deductedVAT == 84)
        #expect(totals.taxableBase == 600)
        #expect(totals.taxableVAT == 126)
        #expect(totals.amountDue == 726)
        #expect(totals.totalGross == 1210)
        // A positive difference is taxed at the rate of the day of supply.
        #expect(row.appliedRatePercent == 21)
        #expect(row.rate?.percent == 21)
    }

    @Test func advancesAboveTheSupplyGiveANegativeBaseAtTheAdvanceRate() throws {
        var document = DocumentFixtures.czkInvoice()
        document.kind = .finalInvoice
        document.lines = [DocumentLine(id: "l1", text: "Dodávka", quantity: 1, unitPrice: 1000, treatment: .taxable(.standard))]
        document.advanceDeductions = [
            AdvanceDeduction(documentNumber: "DD-2023-009", paymentDate: day("2023-12-20"), treatment: .taxable(.reduced), ratePercent: 15, base: 1200, vat: 180),
        ]
        let totals = try DocumentTotals.compute(for: document)
        // § 37a odst. 1: one difference for the one supply, even though the advance was taxed as reduced.
        #expect(totals.rows.count == 1)
        let row = try #require(totals.rows.first)
        #expect(row.treatment == .taxable(.standard))
        #expect(row.base == 1000)
        #expect(row.deductedBase == 1200)
        #expect(row.deductedVAT == 180)
        #expect(row.taxableBase == -200)
        // § 37a odst. 2 písm. b): the 15 % the advance was taxed at, not the 21 % of the day of supply.
        #expect(row.taxableVAT == -30)
        #expect(row.appliedRatePercent == 15)
        #expect(row.rate?.percent == 21)
        #expect(totals.amountDue == -230)
        let codes = Set(DocumentValidator.validate(document).map(\.code))
        #expect(codes.contains(.advancesExceedSupply))
        #expect(codes.contains(.advanceRateDiffers))
    }

    @Test func paymentTaxDocumentFromAdvanceRequest() throws {
        var request = DocumentFixtures.czkInvoice()
        request.kind = .advanceRequest
        request.number = "ZF-2026-001"
        request.taxPointDate = nil
        request.lines = [DocumentLine(id: "l1", text: "Záloha na dodávku", quantity: 1, unitPrice: 1000, treatment: .taxable(.standard))]
        let requestTotals = try DocumentTotals.compute(for: request)
        #expect(requestTotals.amountDue == 1210)

        var receipt = Document.paymentTaxDocument(forAdvanceRequest: request, received: 1210, on: day("2026-11-03"))
        receipt.number = "DD-2026-001"
        #expect(receipt.kind == .paymentTaxDocument)
        #expect(receipt.pricing == .gross)
        #expect(receipt.taxPointDate == day("2026-11-03"))
        #expect(receipt.issueDate == day("2026-11-03"))
        #expect(receipt.relatedDocumentNumber == "ZF-2026-001")
        #expect(receipt.lines.first?.text == "Přijatá platba k zálohové faktuře č. ZF-2026-001")
        let receiptTotals = try DocumentTotals.compute(for: receipt)
        #expect(receiptTotals.taxableBase == 1000)
        #expect(receiptTotals.taxableVAT == 210)
        #expect(receiptTotals.amountDue == 1210)

        let deductions = receipt.advanceDeductions(totals: receiptTotals)
        #expect(deductions.count == 1)
        #expect(deductions.allSatisfy { $0.currency == receipt.currency })
        #expect(deductions.first?.documentNumber == "DD-2026-001")
        #expect(deductions.first?.paymentDate == day("2026-11-03"))
        #expect(deductions.first?.base == 1000)
        #expect(deductions.first?.vat == 210)
        #expect(deductions.first?.ratePercent == 21)

        var finalInvoice = DocumentFixtures.czkInvoice()
        finalInvoice.kind = .finalInvoice
        finalInvoice.lines = request.lines
        finalInvoice.advanceDeductions = deductions
        let finalTotals = try DocumentTotals.compute(for: finalInvoice)
        #expect(finalTotals.taxableBase == 0)
        #expect(finalTotals.taxableVAT == 0)
        #expect(finalTotals.amountDue == 0)
        #expect(DocumentClause.clauses(for: finalInvoice).contains(.advancesDeducted(documentNumbers: ["DD-2026-001"])))
        #expect(request.advanceDeductions(totals: requestTotals).isEmpty)
    }

    @Test func wrongRateCurrencyThrows() {
        var document = DocumentFixtures.euInvoice()
        document.exchangeRate = ExchangeRate(currency: .usd, czkPerAmount: d("21.000"), validFor: day("2026-11-04"), source: .manual)
        #expect(throws: DocumentAmountError.exchangeRateCurrencyMismatch(rate: .usd, document: .eur)) {
            try DocumentTotals.compute(for: document)
        }
    }
}

@Suite struct IssueDeadlineTests {
    @Test func fifteenDaysForDomesticSupplies() {
        #expect(IssueDeadline.lastDay(treatment: .taxable(.standard), taxPoint: day("2026-11-04")) == day("2026-11-19"))
        #expect(IssueDeadline.lastDay(treatment: .exempt(reference: "§ 56"), taxPoint: day("2026-12-31")) == day("2027-01-15"))
    }

    @Test func endOfMonthPlusFifteenForServicesAbroad() {
        #expect(IssueDeadline.lastDay(treatment: .reverseChargeEU, taxPoint: day("2026-11-04")) == day("2026-12-15"))
        #expect(IssueDeadline.lastDay(treatment: .reverseChargeEU, taxPoint: day("2026-11-30")) == day("2026-12-15"))
        #expect(IssueDeadline.lastDay(treatment: .outsideEU, taxPoint: day("2026-02-01")) == day("2026-03-15"))
    }

    @Test func documentTakesTheStrictestDeadline() {
        let eu = DocumentFixtures.euInvoice()
        #expect(IssueDeadline.lastDay(for: eu) == day("2026-12-15"))
        var mixed = eu
        mixed.lines.append(DocumentLine(id: "l2", text: "Domestic", quantity: 1, unitPrice: 10, treatment: .taxable(.standard)))
        #expect(IssueDeadline.lastDay(for: mixed) == day("2026-11-19"))
        var advance = eu
        advance.kind = .advanceRequest
        #expect(IssueDeadline.lastDay(for: advance) == nil)
        var receipt = eu
        receipt.kind = .paymentTaxDocument
        receipt.taxPointDate = day("2026-10-20")
        #expect(IssueDeadline.lastDay(for: receipt) == day("2026-11-15"))
        var empty = eu
        empty.lines = []
        #expect(IssueDeadline.lastDay(for: empty) == nil)
    }
}

@Suite struct DocumentValidatorTests {
    @Test func completeDocumentsHaveNoIssues() {
        #expect(DocumentValidator.validate(DocumentFixtures.euInvoice()).isEmpty)
        #expect(DocumentValidator.validate(DocumentFixtures.czkInvoice()).isEmpty)
        #expect(DocumentValidator.canIssue(DocumentFixtures.euInvoice()))
    }

    @Test func reverseChargeNeedsAnEUCustomerVATID() {
        var document = DocumentFixtures.euInvoice()
        document.customer.vatIdentifier = nil
        #expect(DocumentValidator.validate(document).contains { $0.code == .customerVATIdentifierRequired && $0.isError })
        #expect(!DocumentValidator.canIssue(document))
        document.customer = DocumentFixtures.czechCustomer
        #expect(DocumentValidator.validate(document).contains { $0.code == .customerVATIdentifierNotEU && $0.detail == "CZ25596641" })
    }

    @Test func foreignCurrencyNeedsAnExchangeRate() {
        var document = DocumentFixtures.euInvoice()
        document.exchangeRate = nil
        #expect(DocumentValidator.validate(document).contains { $0.code == .exchangeRateMissing && $0.severity == .warning })
        document.lines[0].treatment = .taxable(.standard)
        document.customer = DocumentFixtures.czechCustomer
        #expect(DocumentValidator.validate(document).contains { $0.code == .exchangeRateMissing && $0.severity == .error })
    }

    @Test func exchangeRateDates() {
        var document = DocumentFixtures.euInvoice()
        document.exchangeRate = ExchangeRate(currency: .eur, czkPerAmount: d("24.000"), validFor: day("2026-10-20"), source: .cnb(order: 201))
        #expect(DocumentValidator.validate(document).contains { $0.code == .exchangeRateStale && $0.severity == .warning && $0.detail == "2026-10-20" })
        document.exchangeRate = ExchangeRate(currency: .eur, czkPerAmount: d("24.000"), validFor: day("2026-11-05"), source: .cnb(order: 213))
        #expect(DocumentValidator.validate(document).contains { $0.code == .exchangeRateAfterTaxPoint && $0.isError })
        // Four days back is a long weekend, not a stale table.
        document.exchangeRate = ExchangeRate(currency: .eur, czkPerAmount: d("24.000"), validFor: day("2026-10-31"), source: .cnb(order: 210))
        #expect(!DocumentValidator.validate(document).contains { $0.code == .exchangeRateStale })
        document.exchangeRate = ExchangeRate(currency: .usd, czkPerAmount: d("21.000"), validFor: day("2026-11-04"), source: .manual)
        #expect(DocumentValidator.validate(document).contains { $0.code == .exchangeRateCurrencyMismatch && $0.detail == "USD" })
    }

    @Test func datesLinesAndNumber() {
        var document = DocumentFixtures.czkInvoice()
        document.number = nil
        document.taxPointDate = nil
        document.dueDate = day("2026-11-01")
        document.lines[0].text = "  "
        document.lines[1].quantity = -1
        document.lines[2].discountPercent = 120
        let issues = DocumentValidator.validate(document)
        let codes = Set(issues.map(\.code))
        #expect(codes.isSuperset(of: [.numberMissing, .taxPointDateMissing, .dueDateBeforeIssueDate, .lineTextMissing, .lineQuantityNegative, .lineDiscountOutOfRange]))
        #expect(issues.contains { $0.code == .lineTextMissing && $0.lineID == "l1" })
        #expect(issues.contains { $0.code == .lineQuantityNegative && $0.lineID == "l2" })
        #expect(!DocumentValidator.validate(document, forIssue: false).contains { $0.code == .numberMissing })
    }

    @Test func addressNeedsATwoLetterCountryCode() {
        var document = DocumentFixtures.czkInvoice()
        document.customer.address = PostalAddress(street: "Krátká 1", city: "Brno", postalCode: "602 00", countryCode: "Czechia")
        #expect(DocumentValidator.validate(document).contains { $0.code == .customerAddressIncomplete && $0.isError })
        document.customer.address = PostalAddress(street: "Krátká 1", city: "Brno", postalCode: "602 00", countryCode: "cz")
        #expect(!DocumentValidator.validate(document).contains { $0.code == .customerAddressIncomplete })
        document.customer.address = PostalAddress(street: "Krátká 1", city: "Brno", postalCode: "602 00", countryCode: "C1")
        #expect(DocumentValidator.validate(document).contains { $0.code == .customerAddressIncomplete })
    }

    @Test func taxPointAfterIssueDateCitesTheTimingRule() {
        var document = DocumentFixtures.czkInvoice()
        document.taxPointDate = day("2026-11-06")
        let issue = DocumentValidator.validate(document).first { $0.code == .taxPointAfterIssueDate }
        #expect(issue?.severity == .warning)
        #expect(issue?.detail == "2026-11-06")
        #expect(issue?.message(language: .czech).contains("§ 21 odst. 3 ZDPH") == true)
        #expect(issue?.message(language: .czech).hasPrefix("Datum plnění 6. 11. 2026 je po datu vystavení") == true)
        #expect(issue?.message(language: .english).contains("§ 21(3) of the VAT Act") == true)
    }

    @Test func supplierAndCustomerData() {
        var document = DocumentFixtures.czkInvoice()
        document.supplier.vatIdentifier = nil
        document.supplier.identificationNumber = nil
        document.supplier.registryEntry = nil
        document.customer.name = ""
        document.customer.address.city = ""
        let issues = DocumentValidator.validate(document)
        #expect(issues.contains { $0.code == .supplierVATIdentifierMissing && $0.isError })
        #expect(issues.contains { $0.code == .supplierIdentificationNumberMissing && $0.severity == .warning })
        #expect(issues.contains { $0.code == .supplierRegistryEntryMissing && $0.severity == .warning })
        #expect(issues.contains { $0.code == .customerNameMissing && $0.isError })
        #expect(issues.contains { $0.code == .customerAddressIncomplete && $0.isError })
    }

    @Test func lateIssueIsAWarning() {
        var document = DocumentFixtures.czkInvoice()
        document.issueDate = day("2026-11-25")
        document.dueDate = day("2026-12-09")
        let issues = DocumentValidator.validate(document)
        #expect(issues.contains { $0.code == .issuedAfterDeadline && $0.severity == .warning && $0.detail == "2026-11-19" })
        #expect(DocumentValidator.canIssue(document))
    }

    @Test func advanceRules() {
        var document = DocumentFixtures.czkInvoice()
        document.advanceDeductions = [
            AdvanceDeduction(documentNumber: "DD-1", paymentDate: day("2026-10-01"), treatment: .taxable(.standard), ratePercent: 21, base: 100, vat: 21),
        ]
        #expect(DocumentValidator.validate(document).contains { $0.code == .advanceDeductionsOnWrongKind && $0.isError })
        document.kind = .finalInvoice
        document.lines = [DocumentLine(id: "l1", text: "Dodávka", quantity: 1, unitPrice: 50, treatment: .taxable(.standard))]
        let issues = DocumentValidator.validate(document)
        #expect(issues.contains { $0.code == .advancesExceedSupply && $0.severity == .warning })
        #expect(!issues.contains { $0.code == .advanceDeductionsOnWrongKind })
        // Advances above the supply stay a warning on a final invoice (§ 37a odst. 2 písm. b)).
        #expect(!issues.contains { $0.code == .documentTotalNegative })
        document.lines = [DocumentLine(id: "l1", text: "Dodávka", quantity: 1, unitPrice: 1000, treatment: .taxable(.reduced))]
        document.advanceDeductions = [
            AdvanceDeduction(documentNumber: "DD-1", paymentDate: day("2023-12-20"), treatment: .taxable(.reduced), ratePercent: 15, base: 400, vat: 60),
        ]
        #expect(DocumentValidator.validate(document).contains { $0.code == .advanceRateDiffers && $0.severity == .warning })
    }

    @Test func paymentInstructions() {
        var document = DocumentFixtures.czkInvoice()
        document.payment = nil
        #expect(DocumentValidator.validate(document).contains { $0.code == .paymentInstructionsMissing && $0.severity == .warning })
        var eurAccount = DocumentFixtures.bank
        eurAccount.currency = .eur
        document.payment = PaymentInstructions(bankConnection: eurAccount)
        #expect(DocumentValidator.validate(document).contains { $0.code == .bankAccountCurrencyDiffers && $0.detail == "EUR" })
    }

    @Test func advanceRequestIsNotATaxDocument() {
        var document = DocumentFixtures.czkInvoice()
        document.kind = .advanceRequest
        document.taxPointDate = nil
        document.supplier.vatIdentifier = nil
        let issues = DocumentValidator.validate(document)
        #expect(!issues.contains { $0.code == .taxPointDateMissing })
        #expect(!issues.contains { $0.code == .supplierVATIdentifierMissing })
        #expect(DocumentClause.clauses(for: document) == [.notATaxDocument])
    }

    @Test func mixedTreatmentsAndExemptReference() {
        var document = DocumentFixtures.euInvoice()
        document.lines.append(DocumentLine(id: "l2", text: "Domestic", quantity: 1, unitPrice: 10, treatment: .taxable(.standard)))
        document.lines.append(DocumentLine(id: "l3", text: "Exempt", quantity: 1, unitPrice: 10, treatment: .exempt(reference: " ")))
        let issues = DocumentValidator.validate(document)
        #expect(issues.contains { $0.code == .mixedTreatments && $0.severity == .warning })
        #expect(issues.contains { $0.code == .exemptReferenceMissing && $0.lineID == "l3" })
    }

    @Test func everyCodeHasMessagesInBothLanguages() {
        for code in ValidationIssue.Code.allCases {
            let issue = ValidationIssue(code: code, severity: .error, detail: "X")
            for language in DocumentLanguage.allCases {
                let message = issue.message(language: language)
                #expect(!message.isEmpty)
                #expect(!message.contains("{detail}"))
            }
        }
        // Dates are stored as ISO strings and printed the Czech way in Czech messages.
        let issue = ValidationIssue(code: .issuedAfterDeadline, severity: .warning, detail: "2026-11-19")
        #expect(issue.message(language: .czech) == "Doklad je vystaven po lhůtě; měl být vystaven nejpozději 19. 11. 2026 (§ 28 ZDPH).")
        #expect(issue.message(language: .english) == "The document is issued late; the deadline was 2026-11-19 (§ 28 of the VAT Act).")
        #expect(ValidationIssue(code: .advanceDeductedTwice, severity: .error, detail: "DD-1").message(language: .czech).contains("Záloha DD-1 "))
        #expect(issue.id == "issuedAfterDeadline")
        #expect(ValidationIssue(code: .lineTextMissing, severity: .error, lineID: "l1").id == "lineTextMissing#l1")
    }
}

@Suite struct DocumentClauseTests {
    @Test func reverseChargeInvoicePrintsTheClauseAndTheRate() {
        let clauses = DocumentClause.clauses(for: DocumentFixtures.euInvoice())
        #expect(clauses == [.reverseCharge, .exchangeRate(DocumentFixtures.eurRate)])
        #expect(DocumentClause.reverseCharge.text(language: .czech) == "Daň odvede zákazník.")
        #expect(DocumentClause.reverseCharge.text(language: .english).hasPrefix("Daň odvede zákazník – reverse charge"))
        #expect(DocumentClause.exchangeRate(DocumentFixtures.eurRate).text(language: .czech)
                == "Přepočet na Kč kurzem ČNB 24,310 CZK/EUR ze dne 4. 11. 2026 (§ 4 odst. 8 zákona o DPH).")
        #expect(DocumentClause.exchangeRate(DocumentFixtures.eurRate).text(language: .english)
                == "Amounts in CZK converted at the CNB exchange rate 24.310 CZK/EUR of 4 November 2026 (Section 4(8) of the Czech VAT Act).")
        let huf = ExchangeRate(currency: Currency(code: "HUF"), amount: 100, czkPerAmount: d("6.512"), validFor: day("2026-11-04"), source: .cnb(order: 212))
        #expect(DocumentClause.exchangeRate(huf).text(language: .english)
                == "Amounts in CZK converted at the CNB exchange rate 6.512 CZK/100 HUF of 4 November 2026 (Section 4(8) of the Czech VAT Act).")
        #expect(DocumentClause.exchangeRate(huf).text(language: .czech)
                == "Přepočet na Kč kurzem ČNB 6,512 CZK/100 HUF ze dne 4. 11. 2026 (§ 4 odst. 8 zákona o DPH).")
    }

    @Test func otherClausesAndLabels() {
        #expect(DocumentClause.exempt(reference: "§ 56 odst. 3").text(language: .czech)
                == "Osvobozeno od daně podle § 56 odst. 3 zákona č. 235/2004 Sb., o dani z přidané hodnoty.")
        #expect(DocumentClause.notATaxDocument.text(language: .english)
                == "This is not a tax document. A tax document will be issued upon receipt of the payment.")
        #expect(DocumentClause.paymentReceived(on: day("2026-11-03"), advanceNumber: "ZF-2026-001").text(language: .czech)
                == "Daňový doklad k platbě přijaté dne 3. 11. 2026 na základě zálohové faktury č. ZF-2026-001.")
        #expect(DocumentClause.paymentReceived(on: day("2026-11-03"), advanceNumber: nil).text(language: .english)
                == "Tax document for the payment received on 3 November 2026.")
        #expect(DocumentClause.advancesDeducted(documentNumbers: ["DD-1", "DD-2"]).text(language: .english)
                == "Less the advance payments taxed on tax documents No. DD-1, DD-2 (Section 37a of the Czech VAT Act).")
        var outside = DocumentFixtures.euInvoice()
        outside.lines[0].treatment = .outsideEU
        outside.exchangeRate = nil
        #expect(DocumentClause.clauses(for: outside) == [.outsideScope])
        for label in DocumentLabel.allCases {
            #expect(!label.text(language: .czech).isEmpty)
            #expect(!label.text(language: .english).isEmpty)
        }
        #expect(DocumentLabel.amountDue.text(language: .czech) == "K úhradě")
        #expect(DocumentLabel.taxPointDate.text(language: .english) == "Date of taxable supply")
    }
}

@Suite struct DocumentPaymentTests {
    @Test func standardInstructionsDeriveSymbolsFromTheNumber() {
        let instructions = PaymentInstructions.standard(for: "FV-2026-001", bankConnection: DocumentFixtures.bank, currency: .czk)
        #expect(instructions.variableSymbol?.digits == "2026001")
        #expect(instructions.creditorReference?.value == "RF84FV2026001")
        #expect(instructions.qrCode == .qrPlatba)
        #expect(PaymentInstructions.standard(for: "1", bankConnection: DocumentFixtures.bank, currency: .eur).qrCode == .sepa)
        #expect(PaymentInstructions.standard(for: "1", bankConnection: DocumentFixtures.bank, currency: .usd).qrCode == .none)
    }

    @Test func qrPlatbaForTheCZKInvoice() throws {
        let document = DocumentFixtures.czkInvoice()
        let totals = try DocumentTotals.compute(for: document)
        let qr = try #require(document.qrPlatba(totals: totals))
        let encoded = try qr.encoded()
        #expect(encoded == "SPD*1.0*ACC:CZ6508000000192000145399+GIBACZPX*AM:1.27*CC:CZK*RN:NOVAKOVA A SYNOVE S. R. O.*DT:20261119*MSG:FV-2026-001*X-VS:2026001")
        #expect(document.sepaQRCode(totals: totals) == nil)
    }

    @Test func sepaCodeForTheEURInvoice() throws {
        let document = DocumentFixtures.euInvoice()
        let totals = try DocumentTotals.compute(for: document)
        let sepa = try #require(document.sepaQRCode(totals: totals))
        let encoded = try sepa.encoded()
        #expect(encoded == "BCD\n002\n1\nSCT\nGIBACZPX\nNováková a synové s. r. o.\nCZ6508000000192000145399\nEUR1000.00\n\nRF84FV2026001")
        #expect(document.qrPlatba(totals: totals) == nil)
        var unnumbered = document
        unnumbered.number = nil
        #expect(unnumbered.sepaQRCode(totals: totals) == nil)
    }
}

@Suite struct DocumentCodableTests {
    @Test func roundTrip() throws {
        var document = DocumentFixtures.euInvoice()
        document.kind = .finalInvoice
        document.advanceDeductions = [
            AdvanceDeduction(id: "ad1", documentNumber: "DD-2026-001", paymentDate: day("2026-10-01"), treatment: .reverseChargeEU, ratePercent: nil, base: 300, vat: 0),
        ]
        let data = try JSONEncoder().encode(document)
        let back = try JSONDecoder().decode(Document.self, from: data)
        #expect(back == document)
        #expect(back.treatments == [.reverseChargeEU])
        #expect(back.title == "Final invoice – tax document")
        #expect(back.taxPoint == day("2026-11-04"))
    }
}

/// Review fixes: advance deductions, split receipts, negative documents, exchange-rate severity, QR limits.
@Suite struct DocumentAdvanceReviewTests {
    /// A CZK final invoice to the Czech customer with the given lines and deductions.
    static func czkFinalInvoice(lines: [DocumentLine], deductions: [AdvanceDeduction]) -> Document {
        var document = DocumentFixtures.czkInvoice()
        document.kind = .finalInvoice
        document.lines = lines
        document.advanceDeductions = deductions
        return document
    }

    /// A CZK advance request numbered ZF-2026-002.
    static func advanceRequest(lines: [DocumentLine]) -> Document {
        var request = DocumentFixtures.czkInvoice()
        request.kind = .advanceRequest
        request.number = "ZF-2026-002"
        request.taxPointDate = nil
        request.lines = lines
        return request
    }

    @Test func sameAdvanceDeductedTwiceIsAnError() throws {
        let deduction = AdvanceDeduction(documentNumber: "DD-1", paymentDate: day("2026-10-01"), treatment: .taxable(.standard),
                                         ratePercent: 21, base: 1000, vat: 210)
        let duplicate = AdvanceDeduction(documentNumber: "DD-1", paymentDate: day("2026-10-01"), treatment: .taxable(.standard),
                                         ratePercent: 21, base: 1000, vat: 210)
        let document = Self.czkFinalInvoice(
            lines: [DocumentLine(id: "l1", text: "Dodávka", quantity: 1, unitPrice: 5000, treatment: .taxable(.standard))],
            deductions: [deduction, duplicate])
        let issues = DocumentValidator.validate(document)
        #expect(issues.contains { $0.code == .advanceDeductedTwice && $0.isError && $0.detail == "DD-1" })
        #expect(issues.filter { $0.code == .advanceDeductedTwice }.count == 1)
        #expect(!DocumentValidator.canIssue(document))
    }

    @Test func oneAdvanceWithTwoTreatmentsIsNotADuplicate() {
        let document = Self.czkFinalInvoice(
            lines: [DocumentLine(id: "l1", text: "Dodávka", quantity: 1, unitPrice: 5000, treatment: .taxable(.standard)),
                    DocumentLine(id: "l2", text: "Dodávka", quantity: 1, unitPrice: 5000, treatment: .taxable(.reduced))],
            deductions: [
                AdvanceDeduction(documentNumber: "DD-1", paymentDate: day("2026-10-01"), treatment: .taxable(.standard), ratePercent: 21, base: 1000, vat: 210),
                AdvanceDeduction(documentNumber: "DD-1", paymentDate: day("2026-10-01"), treatment: .taxable(.reduced), ratePercent: 12, base: 1000, vat: 120),
            ])
        #expect(!DocumentValidator.validate(document).contains { $0.code == .advanceDeductedTwice })
        #expect(DocumentValidator.canIssue(document))
    }

    @Test func advanceInAnotherCurrencyIsAnError() throws {
        var request = Self.advanceRequest(lines: [DocumentLine(id: "l1", text: "Advance", quantity: 1, unitPrice: 1000, treatment: .taxable(.standard))])
        request.currency = .eur
        var receipt = Document.paymentTaxDocument(forAdvanceRequest: request, received: 1210, on: day("2026-11-03"))
        receipt.number = "DD-2026-002"
        let receiptTotals = try DocumentTotals.compute(for: receipt)
        let deductions = receipt.advanceDeductions(totals: receiptTotals)
        #expect(deductions.first?.currency == .eur)
        #expect(deductions.first?.base == 1000)

        let czkFinal = Self.czkFinalInvoice(
            lines: [DocumentLine(id: "l1", text: "Dodávka", quantity: 1, unitPrice: 30000, treatment: .taxable(.standard))],
            deductions: deductions)
        #expect(DocumentValidator.validate(czkFinal).contains { $0.code == .advanceCurrencyDiffers && $0.isError && $0.detail == "DD-2026-002" })
        #expect(!DocumentValidator.canIssue(czkFinal))

        var eurFinal = czkFinal
        eurFinal.currency = .eur
        eurFinal.exchangeRate = DocumentFixtures.eurRate
        eurFinal.payment = PaymentInstructions.standard(for: "FV-2026-001", bankConnection: DocumentFixtures.bank, currency: .eur)
        #expect(!DocumentValidator.validate(eurFinal).contains { $0.code == .advanceCurrencyDiffers })
    }

    @Test func deductionWithoutCurrencyDecodes() throws {
        let legacy = AdvanceDeduction(id: "ad1", documentNumber: "DD-1", paymentDate: day("2026-10-01"), treatment: .taxable(.standard),
                                      ratePercent: 21, base: 100, vat: 21)
        let data = try JSONEncoder().encode(legacy)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(!json.contains("currency"))
        let decoded = try JSONDecoder().decode(AdvanceDeduction.self, from: data)
        #expect(decoded.currency == nil)
        #expect(decoded == legacy)
        var withCurrency = legacy
        withCurrency.currency = .czk
        let roundTrip = try JSONDecoder().decode(AdvanceDeduction.self, from: try JSONEncoder().encode(withCurrency))
        #expect(roundTrip.currency == .czk)
    }

    @Test func paymentTaxDocumentSplitsMixedRates() throws {
        let request = Self.advanceRequest(lines: [
            DocumentLine(id: "l1", text: "Dodávka A", quantity: 1, unitPrice: 1000, treatment: .taxable(.standard)),
            DocumentLine(id: "l2", text: "Dodávka B", quantity: 1, unitPrice: 1000, treatment: .taxable(.reduced)),
        ])
        let requestTotals = try DocumentTotals.compute(for: request)
        #expect(requestTotals.amountDue == 2330)

        var receipt = Document.paymentTaxDocument(forAdvanceRequest: request, received: 2330, on: day("2026-11-03"))
        receipt.number = "DD-2026-003"
        #expect(receipt.lines.count == 2)
        #expect(receipt.lines.map(\.unitPrice) == [1210, 1120])
        #expect(receipt.lines.first?.text == "Přijatá platba k zálohové faktuře č. ZF-2026-002 (DPH 21 %)")
        #expect(receipt.lines.last?.text == "Přijatá platba k zálohové faktuře č. ZF-2026-002 (DPH 12 %)")
        let receiptTotals = try DocumentTotals.compute(for: receipt)
        #expect(receiptTotals.rows.count == 2)
        let standard = try #require(receiptTotals.rows.first)
        let reduced = try #require(receiptTotals.rows.last)
        #expect(standard.taxableBase == 1000)
        #expect(standard.taxableVAT == 210)
        #expect(reduced.taxableBase == 1000)
        #expect(reduced.taxableVAT == 120)
        #expect(receiptTotals.taxableVAT == 330)
        #expect(receiptTotals.amountDue == 2330)

        let deductions = receipt.advanceDeductions(totals: receiptTotals)
        #expect(deductions.map(\.ratePercent) == [21, 12])

        let finalInvoice = Self.czkFinalInvoice(lines: request.lines, deductions: deductions)
        let finalTotals = try DocumentTotals.compute(for: finalInvoice)
        #expect(finalTotals.rows.allSatisfy { $0.taxableBase == 0 && $0.taxableVAT == 0 })
        #expect(finalTotals.taxableBase == 0)
        #expect(finalTotals.taxableVAT == 0)
        #expect(finalTotals.amountDue == 0)
        let issues = DocumentValidator.validate(finalInvoice)
        #expect(!issues.contains { $0.code == .advancesExceedSupply })
        #expect(!issues.contains { $0.code == .advanceRateDiffers })
    }

    @Test func partialPaymentIsSplitInProportion() throws {
        let request = Self.advanceRequest(lines: [
            DocumentLine(id: "l1", text: "Dodávka A", quantity: 1, unitPrice: 1000, treatment: .taxable(.standard)),
            DocumentLine(id: "l2", text: "Dodávka B", quantity: 1, unitPrice: 1000, treatment: .taxable(.reduced)),
        ])
        let half = Document.paymentTaxDocument(forAdvanceRequest: request, received: 1165, on: day("2026-11-03"))
        #expect(half.lines.map(\.unitPrice) == [605, 560])
        let halfTotals = try DocumentTotals.compute(for: half)
        #expect(halfTotals.rows.map(\.taxableBase) == [500, 500])
        #expect(halfTotals.rows.map(\.taxableVAT) == [105, 60])

        // 1000 × 1210 / 2330 = 519.313…, rounded to 519.31; the reduced line takes the remainder 480.69.
        let part = Document.paymentTaxDocument(forAdvanceRequest: request, received: 1000, on: day("2026-11-03"))
        #expect(part.lines.map(\.unitPrice) == [d("519.31"), d("480.69")])
        #expect(part.lines.reduce(Decimal(0)) { $0 + $1.unitPrice } == 1000)
        let partTotals = try DocumentTotals.compute(for: part)
        #expect(partTotals.rows.map(\.taxableBase) == [d("429.18"), d("429.19")])
        #expect(partTotals.rows.map(\.taxableVAT) == [d("90.13"), d("51.50")])
        #expect(partTotals.amountDue == 1000)
    }

    @Test func paymentForReverseChargeAndDomesticLinesKeepsTheDomesticDeadline() throws {
        let request = Self.advanceRequest(lines: [
            DocumentLine(id: "l1", text: "Consulting", quantity: 1, unitPrice: 1000, treatment: .reverseChargeEU),
            DocumentLine(id: "l2", text: "Domestic service", quantity: 1, unitPrice: 200, treatment: .taxable(.standard)),
        ])
        let receipt = Document.paymentTaxDocument(forAdvanceRequest: request, received: 1242, on: day("2026-11-04"))
        #expect(receipt.lines.map(\.treatment) == [.reverseChargeEU, .taxable(.standard)])
        #expect(receipt.lines.map(\.unitPrice) == [1000, 242])
        let totals = try DocumentTotals.compute(for: receipt)
        #expect(totals.rows.map(\.taxableBase) == [1000, 200])
        #expect(totals.taxableVAT == 42)
        #expect(IssueDeadline.lastDay(for: receipt) == day("2026-11-19"))
    }

    @Test func paymentForASingleTreatmentStaysOneLine() {
        let request = Self.advanceRequest(lines: [
            DocumentLine(id: "l1", text: "Dodávka A", quantity: 1, unitPrice: 1000, treatment: .taxable(.reduced)),
            DocumentLine(id: "l2", text: "Dodávka B", quantity: 2, unitPrice: 500, treatment: .taxable(.reduced)),
        ])
        let receipt = Document.paymentTaxDocument(forAdvanceRequest: request, received: 700, on: day("2026-11-03"))
        #expect(receipt.lines.count == 1)
        #expect(receipt.lines.first?.unitPrice == 700)
        #expect(receipt.lines.first?.treatment == .taxable(.reduced))
        #expect(receipt.lines.first?.text == "Přijatá platba k zálohové faktuře č. ZF-2026-002")
    }

    @Test func advanceTaxedAtTheOldReducedRateIsDeductedFromTheSupply() throws {
        // Cleaning: 15 % reduced rate in 2023, standard 21 % from 2024 (§ 37a odst. 2 písm. a)).
        var document = Self.czkFinalInvoice(
            lines: [DocumentLine(id: "l1", text: "Úklid", quantity: 1, unitPrice: 20000, treatment: .taxable(.standard))],
            deductions: [AdvanceDeduction(documentNumber: "DD-2023-010", paymentDate: day("2023-12-15"), treatment: .taxable(.reduced),
                                          ratePercent: 15, base: 10000, vat: 1500)])
        document.issueDate = day("2024-01-31")
        document.taxPointDate = day("2024-01-31")
        document.dueDate = day("2024-02-14")
        let totals = try DocumentTotals.compute(for: document)
        #expect(totals.rows.count == 1)
        #expect(totals.taxableBase == 10000)
        #expect(totals.taxableVAT == 2100)
        #expect(totals.amountDue == 12100)
        let codes = Set(DocumentValidator.validate(document).map(\.code))
        #expect(codes.contains(.advanceRateDiffers))
        #expect(!codes.contains(.advancesExceedSupply))
    }

    @Test func advanceUnderAThirdRateKeepsItsOwnRowAndWarns() throws {
        let document = Self.czkFinalInvoice(
            lines: [DocumentLine(id: "l1", text: "Dodávka A", quantity: 1, unitPrice: 1000, treatment: .taxable(.standard)),
                    DocumentLine(id: "l2", text: "Dodávka B", quantity: 1, unitPrice: 1000, treatment: .taxable(.reduced))],
            deductions: [AdvanceDeduction(documentNumber: "DD-2023-011", paymentDate: day("2023-12-20"), treatment: .taxable(.secondReduced),
                                          ratePercent: 10, base: 500, vat: 50)])
        let totals = try DocumentTotals.compute(for: document)
        #expect(totals.rows.count == 3)
        let advance = try #require(totals.rows.last)
        #expect(advance.treatment == .taxable(.secondReduced))
        #expect(advance.base == 0)
        #expect(advance.taxableBase == -500)
        #expect(advance.taxableVAT == -50)
        #expect(advance.appliedRatePercent == 10)
        #expect(DocumentValidator.validate(document).contains { $0.code == .advanceRateDiffers && $0.severity == .warning })
    }

    @Test func negativeDifferenceRowReportsTheAppliedRate() throws {
        let document = Self.czkFinalInvoice(
            lines: [DocumentLine(id: "l1", text: "Dodávka", quantity: 1, unitPrice: 800, treatment: .taxable(.reduced))],
            deductions: [AdvanceDeduction(documentNumber: "DD-2023-009", paymentDate: day("2023-12-20"), treatment: .taxable(.reduced),
                                          ratePercent: 15, base: 1200, vat: 180)])
        let totals = try DocumentTotals.compute(for: document)
        let row = try #require(totals.rows.first)
        #expect(row.taxableBase == -400)
        #expect(row.taxableVAT == d("-60.00"))
        #expect(row.appliedRatePercent == 15)
        #expect(row.rate?.percent == 12)
    }

    @Test func deductionOnlyRowReportsTheAdvanceRate() throws {
        let document = Self.czkFinalInvoice(
            lines: [DocumentLine(id: "l1", text: "Consulting", quantity: 1, unitPrice: 1000, treatment: .exempt(reference: "§ 56"))],
            deductions: [AdvanceDeduction(documentNumber: "DD-2023-009", paymentDate: day("2023-12-20"), treatment: .taxable(.reduced),
                                          ratePercent: 15, base: 1200, vat: 180)])
        let totals = try DocumentTotals.compute(for: document)
        let advance = try #require(totals.rows.last)
        #expect(advance.base == 0)
        #expect(advance.taxableVAT == -180)
        #expect(advance.appliedRatePercent == 15)
        #expect(advance.rate?.percent == 12)
        #expect(DocumentValidator.validate(document).contains { $0.code == .advanceRateDiffers })
    }

    @Test func amountDueIsTheBalanceOfWhatWasPaid() throws {
        // Payment of 1000.01 received at 21 %: base 826.45, VAT 173.56.
        let document = Self.czkFinalInvoice(
            lines: [DocumentLine(id: "l1", text: "Dodávka", quantity: 1, unitPrice: 2000, treatment: .taxable(.standard))],
            deductions: [AdvanceDeduction(documentNumber: "DD-2026-004", paymentDate: day("2026-10-01"), treatment: .taxable(.standard),
                                          ratePercent: 21, base: d("826.45"), vat: d("173.56"))])
        let totals = try DocumentTotals.compute(for: document)
        #expect(totals.taxableBase == d("1173.55"))
        #expect(totals.taxableVAT == d("246.45"))
        #expect(totals.amountDue == d("1419.99"))
        let qr = try #require(document.qrPlatba(totals: totals))
        #expect(qr.amount == d("1419.99"))
    }
}

@Suite struct DocumentNegativeAmountTests {
    @Test func negativeInvoiceIsAnError() {
        var document = DocumentFixtures.czkInvoice()
        document.lines = [DocumentLine(id: "l1", text: "Dobropis", quantity: 1, unitPrice: -1000, treatment: .taxable(.standard))]
        #expect(DocumentValidator.validate(document).contains { $0.code == .documentTotalNegative && $0.isError })
        #expect(!DocumentValidator.canIssue(document))
    }

    @Test func discountLineInAPositiveInvoiceIsFine() {
        var document = DocumentFixtures.czkInvoice()
        document.lines = [DocumentLine(id: "l1", text: "Dodávka", quantity: 1, unitPrice: 1000, treatment: .taxable(.standard)),
                          DocumentLine(id: "l2", text: "Sleva", quantity: 1, unitPrice: -100, treatment: .taxable(.standard))]
        #expect(!DocumentValidator.validate(document).contains { $0.code == .documentTotalNegative })
        #expect(DocumentValidator.canIssue(document))
    }

    @Test func receiptMustBePositive() {
        let request = DocumentAdvanceReviewTests.advanceRequest(lines: [
            DocumentLine(id: "l1", text: "Záloha", quantity: 1, unitPrice: 1000, treatment: .taxable(.standard)),
        ])
        var receipt = Document.paymentTaxDocument(forAdvanceRequest: request, received: -500, on: day("2026-11-03"))
        receipt.number = "DD-2026-005"
        #expect(DocumentValidator.validate(receipt).contains { $0.code == .receivedAmountNotPositive && $0.isError })
        #expect(!DocumentValidator.canIssue(receipt))
        var zero = Document.paymentTaxDocument(forAdvanceRequest: request, received: 0, on: day("2026-11-03"))
        zero.number = "DD-2026-006"
        #expect(DocumentValidator.validate(zero).contains { $0.code == .receivedAmountNotPositive })
    }
}

@Suite struct DocumentExchangeRateSeverityTests {
    static func eurFinalInvoice(lines: [DocumentLine], deductions: [AdvanceDeduction]) -> Document {
        var document = DocumentFixtures.euInvoice()
        document.kind = .finalInvoice
        document.customer = DocumentFixtures.czechCustomer
        document.exchangeRate = nil
        document.lines = lines
        document.advanceDeductions = deductions
        return document
    }

    @Test func czechVATRowsThatNetToZeroStillNeedTheRate() {
        let document = Self.eurFinalInvoice(
            lines: [DocumentLine(id: "l1", text: "Supply", quantity: 1, unitPrice: 500, treatment: .taxable(.standard))],
            deductions: [AdvanceDeduction(documentNumber: "DD-1", paymentDate: day("2026-10-01"), treatment: .taxable(.reduced),
                                          ratePercent: 12, base: 875, vat: 105, currency: .eur)])
        #expect(DocumentValidator.validate(document).contains { $0.code == .exchangeRateMissing && $0.isError })
        #expect(!DocumentValidator.canIssue(document))
    }

    @Test func fullyCoveredSupplyStillNeedsTheRate() throws {
        let document = Self.eurFinalInvoice(
            lines: [DocumentLine(id: "l1", text: "Supply", quantity: 1, unitPrice: 1000, treatment: .taxable(.standard))],
            deductions: [AdvanceDeduction(documentNumber: "DD-1", paymentDate: day("2026-10-01"), treatment: .taxable(.standard),
                                          ratePercent: 21, base: 1000, vat: 210, currency: .eur)])
        let totals = try DocumentTotals.compute(for: document)
        #expect(totals.taxableVAT == 0)
        #expect(DocumentValidator.validate(document).contains { $0.code == .exchangeRateMissing && $0.isError })
    }
}

@Suite struct DocumentQRLimitTests {
    static func encodedField(_ key: String, in encoded: String) -> String? {
        encoded.split(separator: "*").first { $0.hasPrefix(key + ":") }.map { String($0.dropFirst(key.count + 1)) }
    }

    @Test func longSupplierNameIsShortened() throws {
        var document = DocumentFixtures.czkInvoice()
        document.supplier.name = "Stavební společnost Novák a synové s.r.o."
        let totals = try DocumentTotals.compute(for: document)
        let qr = try #require(document.qrPlatba(totals: totals))
        let encoded = try qr.encoded()
        let name = try #require(Self.encodedField("RN", in: encoded))
        #expect(name.count <= 35)
        #expect(name.hasPrefix("STAVEBNI SPOLECNOST NOVAK A SYNOVE"))
    }

    @Test func longMessageIsShortened() throws {
        var document = DocumentFixtures.czkInvoice()
        document.payment?.message = String(repeating: "Platba za zboží ", count: 5)
        let totals = try DocumentTotals.compute(for: document)
        let qr = try #require(document.qrPlatba(totals: totals))
        let encoded = try qr.encoded()
        let message = try #require(Self.encodedField("MSG", in: encoded))
        #expect(message.count <= 60)
    }

    @Test func percentEscapeIsNeverCut() throws {
        var document = DocumentFixtures.czkInvoice()
        document.supplier.name = String(repeating: "A", count: 33) + "*BBB"
        let totals = try DocumentTotals.compute(for: document)
        let qr = try #require(document.qrPlatba(totals: totals))
        let encoded = try qr.encoded()
        let name = try #require(Self.encodedField("RN", in: encoded))
        #expect(name == String(repeating: "A", count: 33))
    }
}

/// § 37a odst. 2 ZDPH for the conversion to CZK: a positive difference uses the rate of the day of supply, a
/// negative one the rate that was applied to the advance.
@Suite struct DocumentAdvanceExchangeRateTests {
    static let advanceRate = ExchangeRate(currency: .eur, czkPerAmount: d("25.000"), validFor: day("2026-10-01"), source: .cnb(order: 190))

    /// A EUR final invoice to the Czech customer, converted at the fixture rate 24.310 of 4 November 2026.
    static func eurFinalInvoice(supply: Decimal, deductions: [AdvanceDeduction]) -> Document {
        var document = DocumentFixtures.euInvoice()
        document.kind = .finalInvoice
        document.language = .czech
        document.customer = DocumentFixtures.czechCustomer
        document.lines = [DocumentLine(id: "l1", text: "Dodávka", quantity: 1, unitPrice: supply, treatment: .taxable(.standard))]
        document.advanceDeductions = deductions
        return document
    }

    static func deduction(_ number: String, base: Decimal, vat: Decimal, rate: ExchangeRate?) -> AdvanceDeduction {
        AdvanceDeduction(documentNumber: number, paymentDate: day("2026-10-01"), treatment: .taxable(.standard),
                         ratePercent: 21, base: base, vat: vat, currency: .eur, exchangeRate: rate)
    }

    @Test func negativeDifferenceIsConvertedAtTheAdvancesRate() throws {
        let document = Self.eurFinalInvoice(supply: 1000, deductions: [Self.deduction("DD-2026-001", base: 1200, vat: 252, rate: Self.advanceRate)])
        let totals = try DocumentTotals.compute(for: document)
        let row = try #require(totals.rows.first)
        #expect(row.taxableBase == -200)
        #expect(row.taxableVAT == -42)
        // 25.000 of the advance, not 24.310 of the day of supply (§ 37a odst. 2 písm. b)).
        #expect(row.taxableBaseCZK == d("-5000.00"))
        #expect(row.taxableVATCZK == d("-1050.00"))
        #expect(row.exchangeRate == Self.advanceRate)
        #expect(totals.taxableBaseCZK == d("-5000.00"))
        #expect(totals.exchangeRate == DocumentFixtures.eurRate)
        #expect(totals.advanceExchangeRates == [Self.advanceRate])
        let codes = Set(DocumentValidator.validate(document).map(\.code))
        #expect(codes.contains(.advancesExceedSupply))
        #expect(!codes.contains(.advanceExchangeRateDiffers))
        // The document explains the rate it used, whether or not the caller passes the totals.
        let clauses = DocumentClause.clauses(for: document, totals: totals)
        #expect(clauses == [.advancesDeducted(documentNumbers: ["DD-2026-001"]), .exchangeRate(DocumentFixtures.eurRate),
                            .advanceExchangeRate(Self.advanceRate)])
        #expect(DocumentClause.clauses(for: document) == clauses)
        #expect(DocumentClause.advanceExchangeRate(Self.advanceRate).text(language: .czech)
                == "Záporný rozdíl základu daně přepočten kurzem ČNB 25,000 CZK/EUR ze dne 1. 10. 2026, uplatněným u přijaté zálohy (§ 37a odst. 2 písm. b) zákona o DPH).")
        #expect(DocumentClause.advanceExchangeRate(Self.advanceRate).text(language: .english)
                == "The negative difference in the tax base is converted at the CNB exchange rate 25.000 CZK/EUR of 1 October 2026 applied to the advance payment (Section 37a(2)(b) of the Czech VAT Act).")
    }

    @Test func positiveDifferenceKeepsTheDocumentsRate() throws {
        let document = Self.eurFinalInvoice(supply: 1000, deductions: [Self.deduction("DD-2026-001", base: 400, vat: 84, rate: Self.advanceRate)])
        let totals = try DocumentTotals.compute(for: document)
        let row = try #require(totals.rows.first)
        #expect(row.taxableBase == 600)
        #expect(row.taxableBaseCZK == d("14586.00"))
        #expect(row.taxableVATCZK == d("3063.06"))
        #expect(row.exchangeRate == DocumentFixtures.eurRate)
        #expect(totals.advanceExchangeRates.isEmpty)
        #expect(!DocumentValidator.validate(document).contains { $0.code == .advanceExchangeRateDiffers })
        let clauses = DocumentClause.clauses(for: document, totals: totals)
        #expect(clauses == [.advancesDeducted(documentNumbers: ["DD-2026-001"]), .exchangeRate(DocumentFixtures.eurRate)])
    }

    @Test func advancesAtDifferentRatesFallBackToTheDocumentsRateAndWarn() throws {
        let other = ExchangeRate(currency: .eur, czkPerAmount: d("24.000"), validFor: day("2026-10-15"), source: .cnb(order: 200))
        let document = Self.eurFinalInvoice(supply: 1000, deductions: [
            Self.deduction("DD-2026-001", base: 700, vat: 147, rate: Self.advanceRate),
            Self.deduction("DD-2026-002", base: 500, vat: 105, rate: other),
        ])
        let totals = try DocumentTotals.compute(for: document)
        let row = try #require(totals.rows.first)
        #expect(row.taxableBase == -200)
        // § 37a odst. 3 is not computed: the document's rate, and the accountant is asked.
        #expect(row.taxableBaseCZK == d("-4862.00"))
        #expect(row.exchangeRate == DocumentFixtures.eurRate)
        #expect(totals.advanceExchangeRates.isEmpty)
        #expect(DocumentValidator.validate(document).contains { $0.code == .advanceExchangeRateDiffers && $0.severity == .warning })
        #expect(DocumentValidator.canIssue(document))
    }

    @Test func sameRateOnTwoAdvancesIsOneRate() throws {
        let sameDay = ExchangeRate(currency: .eur, czkPerAmount: d("25.000"), validFor: day("2026-10-02"), source: .cnb(order: 191))
        let document = Self.eurFinalInvoice(supply: 1000, deductions: [
            Self.deduction("DD-2026-001", base: 700, vat: 147, rate: Self.advanceRate),
            Self.deduction("DD-2026-002", base: 500, vat: 105, rate: sameDay),
        ])
        let totals = try DocumentTotals.compute(for: document)
        #expect(totals.rows.first?.taxableBaseCZK == d("-5000.00"))
        #expect(!DocumentValidator.validate(document).contains { $0.code == .advanceExchangeRateDiffers })
    }

    @Test func deductionWithoutAnExchangeRateWarnsOnlyOnANegativeDifference() throws {
        var document = Self.eurFinalInvoice(supply: 1000, deductions: [Self.deduction("DD-2026-001", base: 1200, vat: 252, rate: nil)])
        var totals = try DocumentTotals.compute(for: document)
        #expect(totals.rows.first?.taxableBaseCZK == d("-4862.00"))
        #expect(DocumentValidator.validate(document).contains { $0.code == .advanceExchangeRateDiffers })
        document.advanceDeductions = [Self.deduction("DD-2026-001", base: 400, vat: 84, rate: nil)]
        totals = try DocumentTotals.compute(for: document)
        #expect(totals.rows.first?.taxableBaseCZK == d("14586.00"))
        #expect(!DocumentValidator.validate(document).contains { $0.code == .advanceExchangeRateDiffers })
    }

    @Test func czkDocumentsNeverCarryARate() throws {
        var document = DocumentFixtures.czkInvoice()
        document.kind = .finalInvoice
        document.lines = [DocumentLine(id: "l1", text: "Dodávka", quantity: 1, unitPrice: 1000, treatment: .taxable(.standard))]
        document.advanceDeductions = [AdvanceDeduction(documentNumber: "DD-1", paymentDate: day("2026-10-01"), treatment: .taxable(.standard),
                                                       ratePercent: 21, base: 1200, vat: 252, currency: .czk)]
        let totals = try DocumentTotals.compute(for: document)
        #expect(totals.rows.first?.exchangeRate == nil)
        #expect(totals.rows.first?.taxableBaseCZK == -200)
        #expect(!DocumentValidator.validate(document).contains { $0.code == .advanceExchangeRateDiffers })
    }

    @Test func paymentTaxDocumentPassesItsRateToTheDeductions() throws {
        var request = DocumentFixtures.euInvoice()
        request.kind = .advanceRequest
        request.number = "ZF-2026-003"
        request.taxPointDate = nil
        request.customer = DocumentFixtures.czechCustomer
        request.lines = [DocumentLine(id: "l1", text: "Záloha", quantity: 1, unitPrice: 1000, treatment: .taxable(.standard))]
        request.exchangeRate = nil
        var receipt = Document.paymentTaxDocument(forAdvanceRequest: request, received: 1210, on: day("2026-10-01"))
        receipt.number = "DD-2026-001"
        receipt.exchangeRate = Self.advanceRate
        let totals = try DocumentTotals.compute(for: receipt)
        let deductions = receipt.advanceDeductions(totals: totals)
        let deduction = try #require(deductions.first)
        #expect(deductions.count == 1)
        #expect(deduction.currency == .eur)
        #expect(deduction.exchangeRate == Self.advanceRate)
        #expect(deduction.base == 1000)
        #expect(deduction.vat == 210)
        #expect(deduction.ratePercent == 21)
        // Round trip through JSON keeps the rate; a deduction stored without one decodes with nil.
        let data = try JSONEncoder().encode(deduction)
        #expect(try JSONDecoder().decode(AdvanceDeduction.self, from: data) == deduction)
        var czkReceipt = Document.paymentTaxDocument(forAdvanceRequest: DocumentAdvanceReviewTests.advanceRequest(lines: request.lines),
                                                     received: 1210, on: day("2026-10-01"))
        czkReceipt.number = "DD-2026-002"
        let czkDeductions = czkReceipt.advanceDeductions(totals: try DocumentTotals.compute(for: czkReceipt))
        #expect(czkDeductions.first?.exchangeRate == nil)
        #expect(czkDeductions.first?.currency == .czk)
    }
}
