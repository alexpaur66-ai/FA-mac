import Foundation
import GRDB
import Testing
import InvoicingCore
@testable import InvoicingData

@Suite struct StatementAcceptTests {
    private static let today = Fixtures.day("2026-11-15")

    private func line(_ id: String, _ amount: String, vs: String? = nil, on day: String = "2026-11-12") -> BankTransaction {
        BankTransaction(id: id, statementID: "st-1", bookedOn: Fixtures.day(day), amount: Money(Fixtures.d(amount), .czk), variableSymbol: vs)
    }

    /// Issued "doc-cz" (VS 2026001) and "doc-2" (VS 2026002), 12 100 CZK each, and the statement with `lines`.
    private func prepared(_ lines: [BankTransaction]) throws -> AppDatabase {
        let database = try Fixtures.prepared()
        let documents = DocumentStore(database)
        try documents.saveDraft(Fixtures.czkDraft(), now: Fixtures.now)
        _ = try documents.issue(id: "doc-cz", seriesID: "fv", now: Fixtures.now)
        try documents.saveDraft(Fixtures.czkDraft(id: "doc-2"), now: Fixtures.now)
        _ = try documents.issue(id: "doc-2", seriesID: "fv", now: Fixtures.now)
        try StatementStore(database).importStatement(StatementStoreTests.statement(), transactions: lines, now: Fixtures.now)
        return database
    }

    private func lineState(_ database: AppDatabase, _ id: String) throws -> (TransactionMatchState, String?) {
        let line = try #require(try StatementStore(database).transactions(in: "st-1").first { $0.id == id })
        return (line.matchState, line.matchedDocumentID)
    }

    @Test func aLineBecomesAPaymentOnce() throws {
        let database = try prepared([line("a", "12100", vs: "2026001")])
        let store = StatementStore(database)
        let accepted = try store.recordPayment(fromLine: "a", documentID: "doc-cz", now: Fixtures.now)
        #expect(accepted.linked == false)
        let payments = try DocumentStore(database).payments(for: "doc-cz")
        #expect(payments.map(\.id) == [accepted.paymentID])
        #expect(payments.first?.bankTransactionID == "a")
        #expect(payments.first?.paidOn == Fixtures.day("2026-11-12"))
        #expect(payments.first?.amount == Money(Fixtures.d("12100"), .czk))
        let state = try lineState(database, "a")
        #expect(state.0 == .manual)
        #expect(state.1 == "doc-cz")
        #expect(try DocumentStore(database).state(for: "doc-cz", today: Self.today).settlement == .paid)
        #expect(throws: DataError.bankLineResolved("a")) {
            try store.recordPayment(fromLine: "a", documentID: "doc-2", now: Fixtures.now)
        }
    }

    @Test func aLineConfirmsAPaymentTypedByHand() throws {
        let database = try prepared([line("a", "12099.50", vs: "2026001"), line("b", "12000", vs: "2026001")])
        let documents = DocumentStore(database)
        let typed = try documents.recordPayment(documentID: "doc-cz", on: Fixtures.day("2026-11-10"), amount: Money(Fixtures.d("12100"), .czk),
                                                now: Fixtures.now)
        let store = StatementStore(database)
        #expect(throws: DataError.bankLineMismatch(transactionID: "b", paymentID: typed.id)) {
            try store.link(line: "b", toPayment: typed.id, now: Fixtures.now)
        }
        let accepted = try store.link(line: "a", toPayment: typed.id, now: Fixtures.now)
        #expect(accepted == BankAcceptance(transactionID: "a", documentID: "doc-cz", paymentID: typed.id, linked: true))
        let payments = try documents.payments(for: "doc-cz")
        #expect(payments.count == 1)
        #expect(payments.first?.bankTransactionID == "a")
        #expect(payments.first?.amount == Money(Fixtures.d("12100"), .czk))
        #expect(try lineState(database, "a").0 == .manual)
    }

    @Test func acceptExactMatchesAndUndoIt() throws {
        let database = try prepared([line("a", "12100", vs: "2026001", on: "2026-11-11"), line("b", "12100", vs: "2026002"), line("c", "500")])
        let documents = DocumentStore(database)
        let typed = try documents.recordPayment(documentID: "doc-cz", on: Fixtures.day("2026-11-10"), amount: Money(Fixtures.d("12100"), .czk),
                                                now: Fixtures.now)
        let store = StatementStore(database)
        let accepted = try store.acceptExactMatches(statementID: "st-1", today: Self.today, now: Fixtures.now)
        #expect(accepted.map(\.transactionID) == ["a", "b"])
        #expect(accepted.map(\.linked) == [true, false])
        #expect(accepted.first?.paymentID == typed.id)
        #expect(try lineState(database, "a").0 == .automatic)
        #expect(try lineState(database, "b").0 == .automatic)
        #expect(try lineState(database, "c").0 == .unmatched)
        #expect(try documents.payments(for: "doc-cz").count == 1)
        #expect(try documents.payments(for: "doc-2").map(\.bankTransactionID) == ["b"])

        try store.undo(accepted, now: Fixtures.now)
        #expect(try documents.payments(for: "doc-2").isEmpty)
        #expect(try documents.payments(for: "doc-cz").map(\.id) == [typed.id])
        #expect(try documents.payments(for: "doc-cz").first?.bankTransactionID == nil)
        #expect(try lineState(database, "a").0 == .unmatched)
        #expect(try lineState(database, "b").0 == .unmatched)
        // Nothing left to accept twice: a second run does the same again.
        #expect(try store.acceptExactMatches(statementID: "st-1", today: Self.today, now: Fixtures.now).count == 2)
    }

    @Test func undoSkipsAPaymentDeletedInTheMeantime() throws {
        let database = try prepared([line("a", "12100", vs: "2026001", on: "2026-11-11"), line("b", "12100", vs: "2026002")])
        let documents = DocumentStore(database)
        let typed = try documents.recordPayment(documentID: "doc-cz", on: Fixtures.day("2026-11-10"), amount: Money(Fixtures.d("12100"), .czk),
                                                now: Fixtures.now)
        let store = StatementStore(database)
        let accepted = try store.acceptExactMatches(statementID: "st-1", today: Self.today, now: Fixtures.now)
        #expect(accepted.map(\.transactionID) == ["a", "b"])
        let recorded = try #require(accepted.last)
        // Deleting the payment recorded from the automatic match returns its line to Unmatched.
        try documents.deletePayment(id: recorded.paymentID, now: Fixtures.now)
        #expect(try lineState(database, "b").0 == .unmatched)
        #expect(try lineState(database, "b").1 == nil)

        try store.undo(accepted, now: Fixtures.now)
        #expect(try documents.payments(for: "doc-2").isEmpty)
        #expect(try documents.payments(for: "doc-cz").map(\.id) == [typed.id])
        #expect(try documents.payments(for: "doc-cz").first?.bankTransactionID == nil)
        #expect(try lineState(database, "a").0 == .unmatched)
        #expect(try lineState(database, "b").0 == .unmatched)
    }

    @Test func aPaymentWithAnIssuedTaxDocumentCanStillBeConfirmed() throws {
        let database = try Fixtures.prepared()
        try Fixtures.addAdvanceSeries(database)
        let advance = try Fixtures.issuedAdvance(database)
        _ = try Fixtures.issuedReceipt(database, advance: advance)
        let payment = try #require(try DocumentStore(database).payments(for: advance.id).first)
        let store = StatementStore(database)
        try store.importStatement(StatementStoreTests.statement(), transactions: [line("a", "12100", vs: "2026001", on: "2026-11-10")],
                                  now: Fixtures.now)
        let accepted = try store.link(line: "a", toPayment: payment.id, now: Fixtures.now)
        #expect(try DocumentStore(database).payments(for: advance.id).first?.bankTransactionID == "a")
        try store.undo([accepted], now: Fixtures.now)
        #expect(try DocumentStore(database).payments(for: advance.id).first?.bankTransactionID == nil)
        // Its money stays locked.
        #expect(throws: (any Error).self) {
            try database.queue.write { db in
                try db.execute(sql: "UPDATE documentPayment SET amount = 1 WHERE id = ?", arguments: [payment.id])
            }
        }
    }

    @Test func moneyOutBecomesARefund() throws {
        let database = try prepared([line("a", "-100")])
        let documents = DocumentStore(database)
        _ = try documents.recordPayment(documentID: "doc-cz", on: Fixtures.day("2026-11-10"), amount: Money(Fixtures.d("12200"), .czk),
                                        now: Fixtures.now)
        let accepted = try StatementStore(database).recordPayment(fromLine: "a", documentID: "doc-cz", now: Fixtures.now)
        let refund = try #require(try documents.payments(for: "doc-cz").first { $0.id == accepted.paymentID })
        #expect(refund.kind == .refund)
        #expect(refund.amount == Money(Fixtures.d("-100"), .czk))
        #expect(try documents.state(for: "doc-cz", today: Self.today).settlement == .paid)
    }
}
