import Foundation
import GRDB
import Testing
import InvoicingCore
@testable import InvoicingData

@Suite struct BankMatcherTests {
    private static let today = Fixtures.day("2026-11-15")
    private static let payer = "DE89 3704 0044 0532 0130 00"

    /// Two issued CZK invoices of 12 100 CZK: "doc-cz" (VS 2026001) and "doc-2" (VS 2026002).
    private func twoInvoices() throws -> AppDatabase {
        let database = try Fixtures.prepared()
        let documents = DocumentStore(database)
        try documents.saveDraft(Fixtures.czkDraft(), now: Fixtures.now)
        _ = try documents.issue(id: "doc-cz", seriesID: "fv", now: Fixtures.now)
        try documents.saveDraft(Fixtures.czkDraft(id: "doc-2"), now: Fixtures.now)
        _ = try documents.issue(id: "doc-2", seriesID: "fv", now: Fixtures.now)
        return database
    }

    private func line(_ id: String, _ amount: String, vs: String? = nil, on day: String = "2026-11-12", account: String? = nil,
                      currency: Currency = .czk, state: TransactionMatchState = .unmatched) -> BankTransaction {
        BankTransaction(id: id, statementID: "st-1", bookedOn: Fixtures.day(day), amount: Money(Fixtures.d(amount), currency),
                        counterpartyAccount: account, variableSymbol: vs, matchState: state)
    }

    private func propose(_ database: AppDatabase, _ lines: [BankTransaction],
                         accounts: [String: [String: Int]] = [:]) throws -> [BankMatchProposal] {
        let documents = DocumentStore(database)
        let states = try documents.states(DocumentFilter(status: .issued), today: Self.today)
        let payments = try states.flatMap { try documents.payments(for: $0.id) }
        return BankMatcher.propose(lines, documents: states, payments: payments, confirmedAccounts: accounts)
    }

    @Test func symbolAndAmountWithinTheToleranceIsAMatch() throws {
        let database = try twoInvoices()
        let proposals = try propose(database, [line("a", "12100", vs: "2026001"), line("b", "12099.50", vs: "002026002", on: "2026-11-13")])
        #expect(proposals.map(\.lane) == [.matched, .matched])
        #expect(proposals.map { $0.candidates.map(\.documentID) } == [["doc-cz"], ["doc-2"]])
        #expect(proposals.first?.candidates.first?.reason == .variableSymbolAndAmount)
    }

    @Test func aDifferentAmountWithTheSymbolIsASuggestion() throws {
        let database = try twoInvoices()
        let proposals = try propose(database, [line("a", "6000", vs: "2026001"), line("b", "12101.50", vs: "2026002")])
        #expect(proposals.map(\.lane) == [.suggested, .suggested])
        #expect(proposals.flatMap { $0.candidates.map(\.reason) } == [.variableSymbol, .variableSymbol])
    }

    @Test func aSecondIdenticalLineIsNotASecondExactMatch() throws {
        let database = try twoInvoices()
        let proposals = try propose(database, [line("b", "12100", vs: "2026001", on: "2026-11-13"), line("a", "12100", vs: "2026001")])
        // Booking order: "a" (12 Nov) is matched, "b" would overpay.
        #expect(proposals.map(\.transaction.id) == ["a", "b"])
        #expect(proposals.map(\.lane) == [.matched, .suggested])
        #expect(proposals.last?.candidates.map(\.reason) == [.variableSymbol])
    }

    @Test func aPaymentRecordedByHandIsAlreadyRecorded() throws {
        let database = try twoInvoices()
        let payment = try DocumentStore(database).recordPayment(documentID: "doc-cz", on: Fixtures.day("2026-11-10"),
                                                                amount: Money(Fixtures.d("12100"), .czk), now: Fixtures.now)
        let near = try propose(database, [line("a", "12100", vs: "2026001", on: "2026-11-12")])
        #expect(near.first?.lane == .alreadyRecorded)
        #expect(near.first?.candidates == [BankMatchCandidate(documentID: "doc-cz", reason: .recordedPayment, paymentID: payment.id)])
        // Ten days apart it is a new payment: the invoice is paid, so the line would overpay it.
        let far = try propose(database, [line("a", "12100", vs: "2026001", on: "2026-11-20")])
        #expect(far.first?.lane == .suggested)
        #expect(far.first?.candidates.map(\.reason) == [.variableSymbol])
        // One hand-recorded payment confirms one line only.
        let twice = try propose(database, [line("a", "12100", vs: "2026001", on: "2026-11-11"), line("b", "12100", vs: "2026001", on: "2026-11-12")])
        #expect(twice.map(\.lane) == [.alreadyRecorded, .suggested])
    }

    @Test func twoInstalmentsRecordedByHandAreBothAlreadyRecorded() throws {
        let database = try twoInvoices()
        let store = DocumentStore(database)
        let first = try store.recordPayment(documentID: "doc-cz", on: Fixtures.day("2026-11-01"),
                                            amount: Money(Fixtures.d("6050"), .czk), now: Fixtures.now)
        let second = try store.recordPayment(documentID: "doc-cz", on: Fixtures.day("2026-11-06"),
                                             amount: Money(Fixtures.d("6050"), .czk), now: Fixtures.now)
        // The 4 Nov line is closest to the second payment, but the 9 Nov line can only be the second one: each
        // line confirms one payment instead of the later line overpaying the invoice.
        let proposals = try propose(database, [line("a", "6050", vs: "2026001", on: "2026-11-04"),
                                               line("b", "6050", vs: "2026001", on: "2026-11-09")])
        #expect(proposals.map(\.lane) == [.alreadyRecorded, .alreadyRecorded])
        let paired: [[String?]] = [[first.id], [second.id]]
        #expect(proposals.map { $0.candidates.map(\.paymentID) } == paired)
    }

    @Test func aKnownPayerAccountSuggestsItsClientsDocuments() throws {
        let database = try twoInvoices()
        let account = try #require(BankMatcher.normalizedAccount(Self.payer))
        let known = try propose(database, [line("a", "12100", account: Self.payer)], accounts: [account: ["cust-cz": 2]])
        #expect(known.first?.lane == .suggested)
        #expect(Set(known.first?.candidates.map(\.documentID) ?? []) == ["doc-cz", "doc-2"])
        #expect(known.first?.candidates.allSatisfy { $0.reason == .knownAccount } == true)
        // Paid once is not known yet, and two open invoices with the amount leave the line unmatched.
        let once = try propose(database, [line("a", "12100", account: Self.payer)], accounts: [account: ["cust-cz": 1]])
        #expect(once.first?.lane == .unmatched)
    }

    @Test func theOnlyDocumentWithTheAmountIsSuggested() throws {
        let database = try Fixtures.prepared()
        let documents = DocumentStore(database)
        try documents.saveDraft(Fixtures.czkDraft(), now: Fixtures.now)
        _ = try documents.issue(id: "doc-cz", seriesID: "fv", now: Fixtures.now)
        let proposals = try propose(database, [line("a", "12100"), line("b", "500")])
        #expect(proposals.map(\.lane) == [.suggested, .unmatched])
        #expect(proposals.first?.candidates == [BankMatchCandidate(documentID: "doc-cz", reason: .amountOnly)])
    }

    @Test func outgoingLinesOfferOverpaidDocuments() throws {
        let database = try twoInvoices()
        _ = try DocumentStore(database).recordPayment(documentID: "doc-cz", on: Fixtures.day("2026-11-10"),
                                                      amount: Money(Fixtures.d("12200"), .czk), now: Fixtures.now)
        let proposals = try propose(database, [line("a", "-100"), line("b", "-45", on: "2026-11-13")])
        #expect(proposals.map(\.lane) == [.outgoing, .outgoing])
        #expect(proposals.first?.candidates == [BankMatchCandidate(documentID: "doc-cz", reason: .amountOnly)])
        #expect(proposals.last?.candidates.isEmpty == true)
    }

    @Test func anAdvanceAFinalInvoiceSettledIsNoRefundCandidate() throws {
        // 1 000 EUR of § 64 goods, 1 100 received: the 100 surplus is a refund candidate until a final invoice
        // settles all 1 100 as paid in advance, after which the store refuses the refund.
        let (database, advance) = try PaidAdvanceStoreTests.preparedWithGoodsAdvance()
        let store = DocumentStore(database)
        _ = try store.recordPayment(documentID: advance.id, on: Fixtures.day("2026-11-02"), amount: Money(Fixtures.d("1100"), .eur),
                                    now: Fixtures.now)
        let refund = line("a", "-100", currency: .eur)
        #expect(try propose(database, [refund]).first?.candidates == [BankMatchCandidate(documentID: advance.id, reason: .amountOnly)])

        let paid = try store.paidAdvanceCandidates(ofAdvanceRequest: advance.id).map(\.paidAdvance)
        var invoice = PaidAdvanceStoreTests.finalInvoiceDraft(paid: paid)
        invoice.lines = [DocumentLine(id: "l1", text: "Spindle bearing SKF 7014", quantity: 20, unit: "pcs", unitPrice: 100,
                                      treatment: .intraCommunityGoods)]
        try store.saveDraft(invoice, now: Fixtures.now)
        _ = try store.issue(id: "final", seriesID: "fv", now: Fixtures.now)
        let proposals = try propose(database, [refund])
        #expect(proposals.first?.lane == .outgoing)
        #expect(proposals.first?.candidates.isEmpty == true)
    }

    @Test func resolvedLinesAndOtherCurrenciesAreLeftAlone() throws {
        let database = try twoInvoices()
        let proposals = try propose(database, [line("a", "12100", vs: "2026001", state: .ignored),
                                               line("b", "12100", vs: "2026001", currency: .eur)])
        #expect(proposals.map(\.lane) == [.resolved, .unmatched])
    }

    @Test func accountsAreComparedInOneSpelling() {
        #expect(BankMatcher.normalizedAccount("19-2000145399/0800") == "CZ6508000000192000145399")
        #expect(BankMatcher.normalizedAccount(" CZ65 0800 0000 1920 0014 5399 ") == "CZ6508000000192000145399")
        #expect(BankMatcher.normalizedAccount("  ") == nil)
        #expect(BankMatcher.canonicalSymbol("0002026001") == "2026001")
        #expect(BankMatcher.canonicalSymbol("VS: none") == nil)
    }

    @Test func theStoreCountsConfirmedAccountsAndProposesAStatement() throws {
        let database = try twoInvoices()
        let store = StatementStore(database)
        try store.importStatement(StatementStoreTests.statement(), transactions: [
            line("a", "12100", vs: "2026001", on: "2026-11-10", account: Self.payer),
            line("b", "50", on: "2026-11-11", account: "DE89370400440532013000"),
            line("c", "12100", vs: "2026002", on: "2026-11-12", account: Self.payer),
        ], now: Fixtures.now)
        try store.setMatch(transactionID: "a", documentID: "doc-cz", state: .automatic, now: Fixtures.now)
        try store.setMatch(transactionID: "b", documentID: "doc-cz", state: .manual, now: Fixtures.now)
        #expect(try store.confirmedAccounts() == ["DE89370400440532013000": ["cust-cz": 2]])
        let proposals = try store.proposals(statementID: "st-1", today: Self.today)
        #expect(proposals.map(\.lane) == [.resolved, .resolved, .matched])
        #expect(throws: DataError.statementNotFound("nope")) { try store.proposals(statementID: "nope", today: Self.today) }
    }

    @Test func aRefundSentToAnAccountDoesNotConfirmIt() throws {
        let database = try twoInvoices()
        let store = StatementStore(database)
        try store.importStatement(StatementStoreTests.statement(), transactions: [
            line("a", "12100", vs: "2026001", on: "2026-11-10", account: Self.payer),
            line("b", "-100", on: "2026-11-11", account: Self.payer),
        ], now: Fixtures.now)
        try store.setMatch(transactionID: "a", documentID: "doc-cz", state: .automatic, now: Fixtures.now)
        try store.setMatch(transactionID: "b", documentID: "doc-2", state: .manual, now: Fixtures.now)
        #expect(try store.confirmedAccounts() == ["DE89370400440532013000": ["cust-cz": 1]])
    }
}
