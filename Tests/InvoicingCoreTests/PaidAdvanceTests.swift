import Foundation
import Testing
@testable import InvoicingCore

/// Advances paid on § 64 goods, which have no payment tax document, listed on the final invoice as paid in
/// advance (ADR 0012).
@Suite struct PaidAdvanceTests {
    /// The goods invoice as a final invoice: ten bearings at 100 EUR, 1 000 EUR exempt under § 64.
    static func goodsFinalInvoice(paid: [PaidAdvance]?) -> Document {
        var document = DocumentFixtures.euGoodsInvoice()
        document.kind = .finalInvoice
        document.number = "FV-2026-002"
        document.paidAdvances = paid
        return document
    }

    static func paid(_ amount: String, number: String = "ZF-2026-003", on iso: String = "2026-11-02", paymentID: String? = "pay-1",
                     currency: Currency = .eur, treatment: VATTreatment? = .intraCommunityGoods) -> PaidAdvance {
        PaidAdvance(id: "pa-\(number)-\(amount)", advanceNumber: number, paidOn: day(iso), amount: d(amount), currency: currency,
                    paymentID: paymentID, advanceTreatment: treatment)
    }

    @Test func paidInAdvanceReducesOnlyTheAmountDue() throws {
        let document = Self.goodsFinalInvoice(paid: [Self.paid("400")])
        let totals = try DocumentTotals.compute(for: document)
        let row = try #require(totals.rows.first)
        // The § 64 value is never reduced: the base, the value this document reports and its CZK value stay whole.
        #expect(totals.rows.count == 1)
        #expect(row.base == 1000)
        #expect(row.deductedBase == 0)
        #expect(row.taxableBase == 1000)
        #expect(row.taxableBaseCZK == d("24310.00"))
        #expect(row.amountDue == 1000)
        #expect(totals.totalGross == 1000)
        #expect(totals.taxableBase == 1000)
        #expect(totals.paidInAdvance == 400)
        #expect(totals.amountDue == 600)
        #expect(totals.dueBeforePaidInAdvance == 1000)
        #expect(DocumentValidator.validate(document).isEmpty)
        // Nothing was deducted, so no § 37a clause.
        #expect(DocumentClause.clauses(for: document) == [.intraCommunitySupply, .exchangeRate(DocumentFixtures.eurRate)])
    }

    @Test func thePaymentCodesAskForTheBalance() throws {
        let document = Self.goodsFinalInvoice(paid: [Self.paid("400"), Self.paid("100", on: "2026-11-03", paymentID: "pay-2")])
        let totals = try DocumentTotals.compute(for: document)
        #expect(totals.amountDue == 500)
        let code = try #require(document.sepaQRCode(totals: totals))
        #expect(code.amount == 500)
    }

    @Test func otherKindsCountNothingAndAreRefused() throws {
        var invoice = DocumentFixtures.euGoodsInvoice()
        invoice.paidAdvances = [Self.paid("400")]
        #expect(try DocumentTotals.compute(for: invoice).amountDue == 1000)
        #expect(DocumentValidator.validate(invoice).contains { $0.code == .paidAdvancesOnWrongKind && $0.isError })
    }

    @Test func rowsMustBeComplete() {
        let document = Self.goodsFinalInvoice(paid: [
            Self.paid("0"),
            Self.paid("400", number: " ", paymentID: "pay-2"),
            Self.paid("400", paymentID: "pay-3", currency: .czk),
        ])
        let issues = DocumentValidator.validate(document)
        #expect(issues.contains { $0.code == .paidAdvanceAmountNotPositive && $0.isError && $0.detail == "ZF-2026-003" })
        #expect(issues.contains { $0.code == .paidAdvanceNumberMissing && $0.isError })
        #expect(issues.contains { $0.code == .paidAdvanceCurrencyDiffers && $0.isError })
        // One issue per rule, so the rows keep distinct ids.
        #expect(Set(issues.map(\.id)).count == issues.count)
    }

    @Test func aPaymentListedTwiceIsAnError() {
        let twice = Self.goodsFinalInvoice(paid: [Self.paid("300"), Self.paid("100")])
        #expect(DocumentValidator.validate(twice).contains { $0.code == .paidAdvanceListedTwice && $0.isError && $0.detail == "ZF-2026-003" })
        // An advance the app does not know is told apart by its day and amount.
        let external = Self.goodsFinalInvoice(paid: [Self.paid("300", paymentID: nil), Self.paid("300", on: "2026-11-03", paymentID: nil)])
        #expect(!DocumentValidator.validate(external).contains { $0.code == .paidAdvanceListedTwice })
    }

    @Test func anAdvanceUnderAnotherTreatmentIsAPointForTheAccountant() {
        let document = Self.goodsFinalInvoice(paid: [Self.paid("400", treatment: .taxable(.standard)),
                                                     Self.paid("100", number: "ZF-2026-004", paymentID: "pay-2", treatment: nil)])
        let issues = DocumentValidator.validate(document)
        let issue = issues.first { $0.code == .paidAdvanceTreatmentDiffers }
        #expect(issue?.severity == .warning)
        // An unknown treatment (an advance from before the app) is not reported.
        #expect(issue?.detail == "ZF-2026-003")
        #expect(!issues.contains(where: \.isError))
    }

    @Test func advancesAboveTheTotalAreAWarning() throws {
        let document = Self.goodsFinalInvoice(paid: [Self.paid("1200")])
        #expect(try DocumentTotals.compute(for: document).amountDue == -200)
        let issues = DocumentValidator.validate(document)
        #expect(issues.contains { $0.code == .paidInAdvanceExceedsTotal && $0.severity == .warning })
        #expect(!issues.contains { $0.code == .advancesExceedSupply })
        #expect(!issues.contains(where: \.isError))
    }

    @Test func theAdvanceTreatmentFollowsTheLines() {
        let goods = DocumentLine(text: "Bearing", unitPrice: 100, treatment: .intraCommunityGoods)
        let service = DocumentLine(text: "Transport", unitPrice: 50, treatment: .reverseChargeEU)
        #expect(PaidAdvance.treatment(of: [goods, goods]) == .intraCommunityGoods)
        #expect(PaidAdvance.treatment(of: [goods, service]) == .reverseChargeEU)
        #expect(PaidAdvance.treatment(of: []) == nil)
        var advance = DocumentFixtures.euGoodsInvoice()
        advance.kind = .advanceRequest
        #expect(advance.isIntraCommunityGoodsOnly)
        advance.lines.append(service)
        #expect(!advance.isIntraCommunityGoodsOnly)
        advance.lines = []
        #expect(!advance.isIntraCommunityGoodsOnly)
    }

    @Test func documentsSavedBeforeTheFieldDecode() throws {
        let document = Self.goodsFinalInvoice(paid: [Self.paid("400")])
        let data = try JSONEncoder().encode(document)
        #expect(try JSONDecoder().decode(Document.self, from: data) == document)
        // A snapshot written before the field existed has no key: it decodes as nil, and nil is not encoded.
        let plain = DocumentFixtures.euGoodsInvoice()
        let plainData = try JSONEncoder().encode(plain)
        let text = try #require(String(data: plainData, encoding: .utf8))
        #expect(!text.contains("paidAdvances"))
        #expect(try JSONDecoder().decode(Document.self, from: plainData).paidAdvances == nil)
    }

    @Test func messagesNameTheAdvance() {
        let issue = ValidationIssue(code: .paidAdvanceTreatmentDiffers, severity: .warning, detail: "ZF-2026-003")
        #expect(issue.message(language: .czech).hasPrefix("Záloha ZF-2026-003 nebyla vystavena jen na dodání zboží"))
        #expect(issue.message(language: .english).hasPrefix("The advance ZF-2026-003 was not issued for EU goods (§ 64) only"))
        #expect(DocumentLabel.advancesPaid.text(language: .czech) == "Uhrazené zálohy")
        #expect(DocumentLabel.advancesPaid.text(language: .english) == "Advances paid")
    }
}
