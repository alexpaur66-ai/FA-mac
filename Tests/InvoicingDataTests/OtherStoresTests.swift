import Foundation
import Testing
import InvoicingCore
import GRDB
@testable import InvoicingData

@Suite struct ProfileStoreTests {
    @Test func savesAndLoads() throws {
        let database = try AppDatabase()
        let store = ProfileStore(database)
        #expect(try store.load() == nil)
        try store.save(Fixtures.profile, now: Fixtures.now)
        #expect(try store.load() == Fixtures.profile)
        var changed = Fixtures.profile
        changed.footer = "Děkujeme za spolupráci."
        try store.save(changed, now: Fixtures.now)
        #expect(try store.load() == changed)
        #expect(try AuditLog(database).events(entity: "companyProfile", id: "1").count == 2)
    }
}

@Suite struct NumberSeriesStoreTests {
    @Test func savesListsAndPeeks() throws {
        let database = try Fixtures.prepared()
        let store = NumberSeriesStore(database)
        let advances = StoredNumberSeries(name: "Zálohové faktury", kinds: [.advanceRequest],
                                          series: try DocumentNumberSeries(id: "zf", pattern: DocumentNumberPattern(template: "ZF{YYYY}{NNNN}"), year: 2026))
        try store.save(advances, now: Fixtures.now)
        #expect(try store.all().map(\.id) == ["fv", "zf"])
        #expect(try store.series(for: .invoice).map(\.id) == ["fv"])
        #expect(try store.series(for: .advanceRequest).map(\.id) == ["zf"])
        #expect(try store.series(for: .paymentTaxDocument).isEmpty)
        #expect(try store.peekNextNumber(seriesID: "zf", on: Fixtures.day("2026-11-05")) == "ZF20260001")
        #expect(try store.peekNextNumber(seriesID: "fv", on: Fixtures.day("2027-01-02")) == "FV-2027-001")
        #expect(throws: DataError.seriesNotFound("x")) { try store.peekNextNumber(seriesID: "x", on: Fixtures.day("2026-11-05")) }
        try store.delete(id: "zf", now: Fixtures.now)
        #expect(try store.series(id: "zf") == nil)
    }

    @Test func savingNeverLowersTheCounter() throws {
        let database = try Fixtures.prepared()
        let documents = DocumentStore(database)
        try documents.saveDraft(Fixtures.czkDraft(), now: Fixtures.now)
        try documents.issue(id: "doc-cz", seriesID: "fv", now: Fixtures.now)
        // The UI re-saves the series from a stale copy with counter 0 and a new name.
        var stale = try Fixtures.invoiceSeries()
        stale.name = "Vydané faktury"
        try NumberSeriesStore(database).save(stale, now: Fixtures.now)
        let kept = try #require(try NumberSeriesStore(database).series(id: "fv"))
        #expect(kept.name == "Vydané faktury")
        #expect(kept.series.lastCounter == 1)
        #expect(kept.series.lastNumber == "FV-2026-001")
    }

    @Test func savingWithANewTemplateKeepsTheCounter() throws {
        let database = try Fixtures.prepared()
        let documents = DocumentStore(database)
        try documents.saveDraft(Fixtures.czkDraft(id: "a"), now: Fixtures.now)
        try documents.saveDraft(Fixtures.czkDraft(id: "b"), now: Fixtures.now)
        try documents.issue(id: "a", seriesID: "fv", now: Fixtures.now)
        try documents.issue(id: "b", seriesID: "fv", now: Fixtures.now)
        // A form that builds a fresh series with a wider counter: the counter carries on, it does not restart.
        let wider = StoredNumberSeries(name: "Faktury", kinds: [.invoice, .finalInvoice],
                                       series: try DocumentNumberSeries(id: "fv", pattern: DocumentNumberPattern(template: "FV-{YYYY}-{NNNN}"), year: 2026))
        let store = NumberSeriesStore(database)
        try store.save(wider, now: Fixtures.now)
        let kept = try #require(try store.series(id: "fv"))
        #expect(kept.series.pattern.template == "FV-{YYYY}-{NNNN}")
        #expect(kept.series.year == 2026)
        #expect(kept.series.lastCounter == 2)
        #expect(try store.peekNextNumber(seriesID: "fv", on: Fixtures.day("2026-11-06")) == "FV-2026-0003")
    }

    @Test func savingAStaleEarlierYearKeepsTheYearAndCounter() throws {
        let database = try Fixtures.prepared()
        let documents = DocumentStore(database)
        let store = NumberSeriesStore(database)
        try documents.saveDraft(Fixtures.czkDraft(id: "a"), now: Fixtures.now)
        try documents.issue(id: "a", seriesID: "fv", now: Fixtures.now)
        let stale = StoredNumberSeries(name: "Faktury", kinds: [.invoice, .finalInvoice],
                                       series: try DocumentNumberSeries(id: "fv", pattern: DocumentNumberPattern(template: "FV-{YYYY}-{NNN}"), year: 2025))
        try store.save(stale, now: Fixtures.now)
        let kept = try #require(try store.series(id: "fv"))
        #expect(kept.series.year == 2026)
        #expect(kept.series.lastCounter == 1)
        try documents.saveDraft(Fixtures.czkDraft(id: "b"), now: Fixtures.now)
        #expect(try documents.issue(id: "b", seriesID: "fv", now: Fixtures.now).number == "FV-2026-002")

        // A copy from the year before, with a higher counter, does not take the series back a year.
        let later = StoredNumberSeries(name: "Faktury", kinds: [.invoice, .finalInvoice],
                                       series: try DocumentNumberSeries(id: "fv", pattern: DocumentNumberPattern(template: "FV-{YYYY}-{NNN}"), year: 2027, lastCounter: 3))
        try store.save(later, now: Fixtures.now)
        let older = StoredNumberSeries(name: "Faktury", kinds: [.invoice, .finalInvoice],
                                       series: try DocumentNumberSeries(id: "fv", pattern: DocumentNumberPattern(template: "FV-{YYYY}-{NNN}"), year: 2026, lastCounter: 40))
        try store.save(older, now: Fixtures.now)
        let current = try #require(try store.series(id: "fv"))
        #expect(current.series.year == 2027)
        #expect(current.series.lastCounter == 3)
        #expect(try store.peekNextNumber(seriesID: "fv", on: Fixtures.day("2027-01-05")) == "FV-2027-004")
    }

    @Test func aCounterThatDoesNotResetOnlyGrows() throws {
        let database = try AppDatabase()
        let store = NumberSeriesStore(database)
        let running = StoredNumberSeries(name: "Průběžná", kinds: [],
                                         series: try DocumentNumberSeries(id: "p", pattern: DocumentNumberPattern(template: "P{NNNNN}"), resetsYearly: false,
                                                                          year: 2026, lastCounter: 7))
        try store.save(running, now: Fixtures.now)
        let stale = StoredNumberSeries(name: "Průběžná", kinds: [],
                                       series: try DocumentNumberSeries(id: "p", pattern: DocumentNumberPattern(template: "P{NNNNN}"), resetsYearly: false,
                                                                        year: 2025, lastCounter: 2))
        try store.save(stale, now: Fixtures.now)
        let kept = try #require(try store.series(id: "p"))
        #expect(kept.series.lastCounter == 7)
        #expect(kept.series.year == 2026)
        #expect(try store.peekNextNumber(seriesID: "p", on: Fixtures.day("2026-11-05")) == "P00008")
    }
}

@Suite struct NumberSeriesPrefixTests {
    @Test func keepsTheVariableSymbolPrefix() throws {
        let database = try AppDatabase()
        let store = NumberSeriesStore(database)
        try store.save(try Fixtures.invoiceSeries(variableSymbolPrefix: "1"), now: Fixtures.now)
        #expect(try store.series(id: "fv")?.series.variableSymbolPrefix == "1")
        // The prefix is a setting like the name: saving the series without one removes it.
        try store.save(try Fixtures.invoiceSeries(), now: Fixtures.now)
        #expect(try store.series(id: "fv")?.series.variableSymbolPrefix == nil)
    }
}

@Suite struct RateStoreTests {
    @Test func importsDailyFileAndLooksUpTheRateTheCNBWay() throws {
        let database = try AppDatabase()
        let store = RateStore(database)
        #expect(try store.importDaily(Fixtures.cnbDaily, now: Fixtures.now) == 3)
        #expect(try store.rates(for: .eur) == [Fixtures.eurRate])
        // Thursday 5 Nov has no row: the last published rate counts (§ 4 odst. 8 ZDPH, ČNB practice).
        #expect(try store.rate(for: .eur, on: Fixtures.day("2026-11-05")) == Fixtures.eurRate)
        #expect(try store.rate(for: .eur, on: Fixtures.day("2026-11-05"), lookup: .exactDay) == nil)
        #expect(try store.rate(for: .eur, on: Fixtures.day("2026-11-03")) == nil)
        #expect(try store.latestDay(for: .eur) == Fixtures.day("2026-11-04"))
        #expect(try store.latestDay(for: .gbp) == nil)
        let yen = try #require(try store.rate(for: Currency(code: "JPY"), on: Fixtures.day("2026-11-04")))
        #expect(yen.amount == 100)
        #expect(yen.czkPerAmount == Fixtures.d("13.845"))
        #expect(yen.source == .cnb(order: 212))

        // Importing the same file again replaces, it does not duplicate.
        #expect(try store.importDaily(Fixtures.cnbDaily, now: Fixtures.now) == 3)
        #expect(try store.table(for: .eur).count == 1)

        let manual = ExchangeRate(currency: .eur, czkPerAmount: Fixtures.d("24.400"), validFor: Fixtures.day("2026-11-05"), source: .manual)
        try store.save(manual, now: Fixtures.now)
        #expect(try store.rate(for: .eur, on: Fixtures.day("2026-11-05")) == manual)
        #expect(try store.rate(for: .eur, on: Fixtures.day("2026-11-06")) == manual)
        #expect(try store.table(for: .eur).count == 2)
    }

    @Test func rejectsMalformedFiles() throws {
        let store = RateStore(try AppDatabase())
        #expect(throws: CNBRateFile.ParseError.self) { try store.importDaily("nonsense") }
        #expect(try store.rates(for: .eur).isEmpty)
    }
}

@Suite struct StatementStoreTests {
    static func statement(hash: String? = "abc") -> BankStatement {
        BankStatement(id: "st-1", iban: Fixtures.bank.iban, currency: .czk, format: .gpc, periodFrom: Fixtures.day("2026-11-01"),
                      periodTo: Fixtures.day("2026-11-30"), statementNumber: "11/2026", openingBalance: Money(Fixtures.d("1000"), .czk),
                      closingBalance: Money(Fixtures.d("13000"), .czk), fileName: "vypis.gpc", fileSHA256: hash)
    }

    static func transactions() -> [BankTransaction] {
        [
            BankTransaction(id: "tx-1", statementID: "st-1", bookedOn: Fixtures.day("2026-11-10"), amount: Money(Fixtures.d("12100"), .czk),
                            counterpartyAccount: "123456789/0100", counterpartyName: "Odběratel s. r. o.", variableSymbol: "2026001",
                            message: "FV-2026-001", bankReference: "B1"),
            BankTransaction(id: "tx-2", statementID: "st-1", bookedOn: Fixtures.day("2026-11-12"), amount: Money(Fixtures.d("-100"), .czk),
                            counterpartyName: "Banka", message: "Poplatek", bankReference: "B2"),
        ]
    }

    @Test func importsListsAndMatches() throws {
        let database = try Fixtures.prepared()
        let store = StatementStore(database)
        try store.importStatement(Self.statement(), transactions: Self.transactions(), now: Fixtures.now)
        #expect(try store.statements() == [Self.statement()])
        #expect(try store.statement(id: "st-1") == Self.statement())
        #expect(try store.transactions(in: "st-1") == Self.transactions())
        #expect(try store.unmatchedIncoming().map(\.id) == ["tx-1"])

        // The same file again is refused; a different file with the same ids too (primary keys).
        #expect(throws: DataError.duplicateStatement(fileSHA256: "abc")) {
            try store.importStatement(Self.statement(), transactions: [], now: Fixtures.now)
        }

        let documents = DocumentStore(database)
        try documents.saveDraft(Fixtures.czkDraft(), now: Fixtures.now)
        try documents.issue(id: "doc-cz", seriesID: "fv", now: Fixtures.now)
        try store.setMatch(transactionID: "tx-1", documentID: "doc-cz", state: .manual, now: Fixtures.now)
        try store.setMatch(transactionID: "tx-2", documentID: nil, state: .ignored, now: Fixtures.now)
        #expect(try store.unmatchedIncoming().isEmpty)
        let matched = try store.transactions(matchedTo: "doc-cz")
        #expect(matched.map(\.id) == ["tx-1"])
        #expect(matched.first?.matchState == .manual)
        #expect(throws: DataError.documentNotFound("ghost")) { try store.setMatch(transactionID: "tx-1", documentID: "ghost", state: .manual) }
        #expect(throws: DataError.transactionNotFound("tx-9")) { try store.setMatch(transactionID: "tx-9", documentID: nil, state: .ignored) }

        try documents.recordPayment(documentID: "doc-cz", on: Fixtures.day("2026-11-10"), amount: Money(Fixtures.d("12100"), .czk),
                                    bankTransactionID: "tx-1", now: Fixtures.now)
        #expect(try documents.paymentState(for: "doc-cz").isSettled)
        #expect(try documents.payments(for: "doc-cz").first?.bankTransactionID == "tx-1")

        // A statement with matched transactions stays; a transaction with payments cannot be unmatched.
        #expect(throws: DataError.self) { try store.deleteStatement(id: "st-1") }
        #expect(throws: DataError.transactionHasPayments("tx-1")) {
            try store.setMatch(transactionID: "tx-1", documentID: nil, state: .unmatched, now: Fixtures.now)
        }
        // Deleting its last payment returns the line to the unmatched list; then the statement can go and the
        // cascade removes the lines.
        let payment = try #require(try documents.payments(for: "doc-cz").first)
        try documents.deletePayment(id: payment.id, now: Fixtures.now)
        #expect(try store.unmatchedIncoming().map(\.id) == ["tx-1"])
        #expect(try store.transactions(matchedTo: "doc-cz").isEmpty)
        try store.setMatch(transactionID: "tx-1", documentID: nil, state: .unmatched, now: Fixtures.now)
        try store.deleteStatement(id: "st-1", now: Fixtures.now)
        #expect(try store.statements().isEmpty)
        #expect(try store.transactions(in: "st-1").isEmpty)
        #expect(try documents.payments(for: "doc-cz").isEmpty)
    }

    @Test func deletingTheLastPaymentOfALineReleasesIt() throws {
        let database = try Fixtures.prepared()
        let store = StatementStore(database)
        let documents = DocumentStore(database)
        try store.importStatement(Self.statement(), transactions: Self.transactions(), now: Fixtures.now)
        try documents.saveDraft(Fixtures.czkDraft(), now: Fixtures.now)
        try documents.issue(id: "doc-cz", seriesID: "fv", now: Fixtures.now)
        let day = Fixtures.day("2026-11-10")

        // One line split across two payments: deleting one keeps the match, deleting the last releases it.
        let first = try documents.recordPayment(documentID: "doc-cz", on: day, amount: Money(Fixtures.d("5000"), .czk),
                                                bankTransactionID: "tx-1", now: Fixtures.now)
        let second = try documents.recordPayment(documentID: "doc-cz", on: day, amount: Money(Fixtures.d("7100"), .czk),
                                                 bankTransactionID: "tx-1", now: Fixtures.now)
        try documents.deletePayment(id: first.id, now: Fixtures.now)
        #expect(try store.unmatchedIncoming().isEmpty)
        #expect(try store.transactions(matchedTo: "doc-cz").map { $0.id } == ["tx-1"])
        try documents.deletePayment(id: second.id, now: Fixtures.now)
        #expect(try store.unmatchedIncoming().map { $0.id } == ["tx-1"])
        #expect(try store.transactions(matchedTo: "doc-cz").isEmpty)
        let event = try #require(try AuditLog(database).events(entity: "bankTransaction", id: "tx-1").last)
        #expect(event.action == "match")
        #expect(event.details?["state"] == "unmatched")
        #expect(event.details?["reason"] == "payment deleted")

        // A refund from a debit line releases that line the same way.
        try documents.recordPayment(documentID: "doc-cz", on: day, amount: Money(Fixtures.d("12100"), .czk), bankTransactionID: "tx-1", now: Fixtures.now)
        let refund = try documents.recordRefund(documentID: "doc-cz", on: Fixtures.day("2026-11-12"), amount: Money(Fixtures.d("100"), .czk),
                                                bankTransactionID: "tx-2", now: Fixtures.now)
        #expect(try store.transactions(matchedTo: "doc-cz").map { $0.id }.sorted() == ["tx-1", "tx-2"])
        try documents.deletePayment(id: refund.id, now: Fixtures.now)
        #expect(try store.transactions(matchedTo: "doc-cz").map { $0.id } == ["tx-1"])
        #expect(try store.transactions(in: "st-1").first { $0.id == "tx-2" }?.matchState == .unmatched)
    }

    @Test func aBankTransactionIsNeverCountedTwice() throws {
        let database = try Fixtures.prepared()
        let store = StatementStore(database)
        let documents = DocumentStore(database)
        try store.importStatement(Self.statement(), transactions: Self.transactions(), now: Fixtures.now)
        try documents.saveDraft(Fixtures.czkDraft(), now: Fixtures.now)
        try documents.issue(id: "doc-cz", seriesID: "fv", now: Fixtures.now)

        // Recording the payment matches the unmatched line to the document.
        let first = try documents.recordPayment(documentID: "doc-cz", on: Fixtures.day("2026-11-10"), amount: Money(Fixtures.d("12100"), .czk),
                                                bankTransactionID: "tx-1", now: Fixtures.now)
        #expect(try store.unmatchedIncoming().isEmpty)
        #expect(try store.transactions(matchedTo: "doc-cz").map { $0.matchState } == [.manual])

        // The same line again, or more than it brought in, is refused.
        #expect(throws: DataError.transactionOverallocated(id: "tx-1", available: Money(0, .czk), requested: Money(Fixtures.d("12100"), .czk))) {
            try documents.recordPayment(documentID: "doc-cz", on: Fixtures.day("2026-11-10"), amount: Money(Fixtures.d("12100"), .czk),
                                        bankTransactionID: "tx-1", now: Fixtures.now)
        }
        #expect(try documents.paymentState(for: "doc-cz").paid == Money(Fixtures.d("12100"), .czk))
        try documents.deletePayment(id: first.id, now: Fixtures.now)
        #expect(try store.unmatchedIncoming().map { $0.id } == ["tx-1"])
        #expect(throws: DataError.transactionOverallocated(id: "tx-1", available: Money(Fixtures.d("12100"), .czk), requested: Money(Fixtures.d("99999"), .czk))) {
            try documents.recordPayment(documentID: "doc-cz", on: Fixtures.day("2026-11-10"), amount: Money(Fixtures.d("99999"), .czk),
                                        bankTransactionID: "tx-1", now: Fixtures.now)
        }

        // One transfer may be split; the parts never add up to more than the transfer.
        try documents.recordPayment(documentID: "doc-cz", on: Fixtures.day("2026-11-10"), amount: Money(Fixtures.d("5000"), .czk),
                                    bankTransactionID: "tx-1", now: Fixtures.now)
        try documents.recordPayment(documentID: "doc-cz", on: Fixtures.day("2026-11-10"), amount: Money(Fixtures.d("7100"), .czk),
                                    bankTransactionID: "tx-1", now: Fixtures.now)
        #expect(throws: DataError.transactionOverallocated(id: "tx-1", available: Money(0, .czk), requested: Money(Fixtures.d("1"), .czk))) {
            try documents.recordPayment(documentID: "doc-cz", on: Fixtures.day("2026-11-10"), amount: Money(Fixtures.d("1"), .czk),
                                        bankTransactionID: "tx-1", now: Fixtures.now)
        }
        #expect(try documents.paymentState(for: "doc-cz").paid == Money(Fixtures.d("12100"), .czk))

        // A debit is no payment received, and an unknown line is reported as such.
        #expect(throws: DataError.transactionDirectionMismatch(id: "tx-2")) {
            try documents.recordPayment(documentID: "doc-cz", on: Fixtures.day("2026-11-12"), amount: Money(Fixtures.d("100"), .czk),
                                        bankTransactionID: "tx-2", now: Fixtures.now)
        }
        // A refund comes from a debit line, allocated like a credit line; a credit line is no refund.
        #expect(throws: DataError.transactionDirectionMismatch(id: "tx-1")) {
            try documents.recordRefund(documentID: "doc-cz", on: Fixtures.day("2026-11-12"), amount: Money(Fixtures.d("1"), .czk),
                                       bankTransactionID: "tx-1", now: Fixtures.now)
        }
        let refund = try documents.recordRefund(documentID: "doc-cz", on: Fixtures.day("2026-11-12"), amount: Money(Fixtures.d("60"), .czk),
                                                bankTransactionID: "tx-2", now: Fixtures.now)
        #expect(refund.amount == Money(Fixtures.d("-60"), .czk))
        #expect(throws: DataError.transactionOverallocated(id: "tx-2", available: Money(Fixtures.d("40"), .czk), requested: Money(Fixtures.d("50"), .czk))) {
            try documents.recordRefund(documentID: "doc-cz", on: Fixtures.day("2026-11-12"), amount: Money(Fixtures.d("50"), .czk),
                                       bankTransactionID: "tx-2", now: Fixtures.now)
        }
        #expect(try documents.paymentState(for: "doc-cz").paid == Money(Fixtures.d("12040"), .czk))
        try documents.deletePayment(id: refund.id, now: Fixtures.now)
        #expect(throws: DataError.transactionNotFound("nope")) {
            try documents.recordPayment(documentID: "doc-cz", on: Fixtures.day("2026-11-12"), amount: Money(Fixtures.d("100"), .czk),
                                        bankTransactionID: "nope", now: Fixtures.now)
        }
        #expect(throws: DataError.transactionHasPayments("tx-1")) {
            try store.setMatch(transactionID: "tx-1", documentID: nil, state: .unmatched, now: Fixtures.now)
        }
        #expect(throws: DataError.transactionHasPayments("tx-1")) {
            try store.setMatch(transactionID: "tx-1", documentID: nil, state: .ignored, now: Fixtures.now)
        }
    }

    @Test func matchesNeedAnIssuedDocumentAndAConsistentState() throws {
        let database = try Fixtures.prepared()
        let store = StatementStore(database)
        let documents = DocumentStore(database)
        try store.importStatement(Self.statement(), transactions: Self.transactions(), now: Fixtures.now)
        try documents.saveDraft(Fixtures.czkDraft(id: "draft-9"), now: Fixtures.now)
        #expect(throws: DataError.documentNotIssued("draft-9")) {
            try store.setMatch(transactionID: "tx-1", documentID: "draft-9", state: .manual, now: Fixtures.now)
        }
        #expect(throws: DataError.invalidMatch(transactionID: "tx-1", state: .manual)) {
            try store.setMatch(transactionID: "tx-1", documentID: nil, state: .manual, now: Fixtures.now)
        }
        #expect(throws: DataError.invalidMatch(transactionID: "tx-1", state: .automatic)) {
            try store.setMatch(transactionID: "tx-1", documentID: nil, state: .automatic, now: Fixtures.now)
        }
        try documents.saveDraft(Fixtures.czkDraft(id: "doc-cz"), now: Fixtures.now)
        try documents.issue(id: "doc-cz", seriesID: "fv", now: Fixtures.now)
        #expect(throws: DataError.invalidMatch(transactionID: "tx-2", state: .ignored)) {
            try store.setMatch(transactionID: "tx-2", documentID: "doc-cz", state: .ignored, now: Fixtures.now)
        }
        #expect(try store.unmatchedIncoming().map { $0.id } == ["tx-1"])
    }

    @Test func deletingAMatchedDraftReturnsTheLineToTheUnmatchedList() throws {
        let database = try Fixtures.prepared()
        let store = StatementStore(database)
        let documents = DocumentStore(database)
        try store.importStatement(Self.statement(), transactions: Self.transactions(), now: Fixtures.now)
        try documents.saveDraft(Fixtures.czkDraft(id: "draft-9"), now: Fixtures.now)
        // A match to a draft can only come from older data or raw SQL; the store no longer writes one.
        try database.queue.write { db in
            try db.execute(sql: "UPDATE bankTransaction SET matchedDocumentID = 'draft-9', matchState = 'manual' WHERE id = 'tx-1'")
        }
        #expect(try store.unmatchedIncoming().isEmpty)
        try documents.deleteDraft(id: "draft-9", now: Fixtures.now)

        let line = try #require(try store.unmatchedIncoming().first)
        #expect(line.id == "tx-1")
        #expect(line.matchState == .unmatched)
        #expect(line.matchedDocumentID == nil)
        #expect(try store.transactions(in: "st-1").first { $0.id == "tx-1" }?.matchState == .unmatched)
        let event = try #require(try AuditLog(database).events(entity: "bankTransaction", id: "tx-1").last)
        #expect(event.action == "match")
        #expect(event.details?["state"] == "unmatched")
    }

    @Test func refusesForeignCurrencyLinesAndWrongStatementIds() throws {
        let store = StatementStore(try AppDatabase())
        let eurLine = BankTransaction(id: "tx-e", statementID: "st-1", bookedOn: Fixtures.day("2026-11-10"), amount: Money(Fixtures.d("10"), .eur))
        #expect(throws: DataError.currencyMismatch(expected: .czk, actual: .eur)) {
            try store.importStatement(Self.statement(hash: nil), transactions: [eurLine])
        }
        let stray = BankTransaction(id: "tx-s", statementID: "other", bookedOn: Fixtures.day("2026-11-10"), amount: Money(Fixtures.d("10"), .czk))
        #expect(throws: DataError.statementNotFound("other")) {
            try store.importStatement(Self.statement(hash: nil), transactions: [stray])
        }
        #expect(try store.statements().isEmpty)
    }
}
