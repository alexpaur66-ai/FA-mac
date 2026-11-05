import Foundation
import Testing
import InvoicingCore
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

        // A statement with matched transactions stays; after unmatching it can go, and the cascade removes the lines.
        #expect(throws: DataError.self) { try store.deleteStatement(id: "st-1") }
        try store.setMatch(transactionID: "tx-1", documentID: nil, state: .unmatched, now: Fixtures.now)
        try store.deleteStatement(id: "st-1", now: Fixtures.now)
        #expect(try store.statements().isEmpty)
        #expect(try store.transactions(in: "st-1").isEmpty)
        #expect(try documents.payments(for: "doc-cz").first?.bankTransactionID == nil)
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
