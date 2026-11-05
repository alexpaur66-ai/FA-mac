import Foundation
import GRDB
import Testing
import InvoicingCore
@testable import InvoicingData

@Suite struct DocumentStoreTests {
    @Test func draftRoundTripAndSummary() throws {
        let database = try Fixtures.prepared()
        let store = DocumentStore(database)
        let draft = Fixtures.czkDraft()
        try store.saveDraft(draft, now: Fixtures.now)

        let stored = try store.document(id: draft.id)
        #expect(stored == draft)
        let summary = try #require(try store.summary(id: draft.id))
        #expect(summary.status == .draft)
        #expect(summary.number == nil)
        #expect(summary.kind == .invoice)
        #expect(summary.customerID == "cust-cz")
        #expect(summary.customerName == "Odběratel s. r. o.")
        #expect(summary.issueDate == Fixtures.day("2026-11-05"))
        #expect(summary.taxPointDate == Fixtures.day("2026-11-04"))
        #expect(summary.totalGross == Money(Fixtures.d("12100"), .czk))
        #expect(summary.amountDue == Money(Fixtures.d("12100"), .czk))
        #expect(summary.taxableVATCZK == Money(Fixtures.d("2100"), .czk))
        #expect(summary.issuedAt == nil)
        #expect(summary.variableSymbol == nil)

        // Saving a draft marked issued or numbered keeps it a draft: only issue() issues.
        var sneaky = draft
        sneaky.status = .issued
        sneaky.number = "FV-2026-999"
        try store.saveDraft(sneaky, now: Fixtures.now)
        let again = try #require(try store.document(id: draft.id))
        #expect(again.status == .draft)
        #expect(again.number == nil)
    }

    @Test func draftWithoutComputableAmountsHasNoTotals() throws {
        let database = try Fixtures.prepared()
        let store = DocumentStore(database)
        var draft = Fixtures.eurDraft()
        // A rate in the wrong currency makes DocumentTotals throw; the draft is still saved.
        draft.exchangeRate = ExchangeRate(currency: .usd, czkPerAmount: Fixtures.d("21.123"), validFor: Fixtures.day("2026-11-04"), source: .manual)
        try store.saveDraft(draft, now: Fixtures.now)
        let summary = try #require(try store.summary(id: draft.id))
        #expect(summary.totalGross == nil)
        #expect(summary.amountDue == nil)
        #expect(try store.document(id: draft.id) == draft)
    }

    @Test func issuingNumbersFreezesAndAudits() throws {
        let database = try Fixtures.prepared()
        let store = DocumentStore(database)
        let draft = Fixtures.czkDraft()
        try store.saveDraft(draft, now: Fixtures.now)
        let later = Fixtures.now.addingTimeInterval(60)

        let issued = try store.issue(id: draft.id, seriesID: "fv", now: later)
        #expect(issued.number == "FV-2026-001")
        #expect(issued.status == .issued)
        #expect(issued.payment?.bankConnection == Fixtures.bank)
        #expect(issued.payment?.variableSymbol?.digits == "2026001")
        #expect(issued.payment?.creditorReference?.value == "RF84FV2026001")
        #expect(issued.payment?.qrCode == .qrPlatba)
        let stored = try store.document(id: draft.id)
        #expect(stored == issued)

        let summary = try #require(try store.summary(id: draft.id))
        #expect(summary.number == "FV-2026-001")
        #expect(summary.status == .issued)
        #expect(summary.issuedAt == "2026-11-05T05:01:00Z")
        #expect(summary.variableSymbol == "2026001")
        #expect(summary.amountDue == Money(Fixtures.d("12100"), .czk))

        // The series advanced in the same transaction.
        let series = try #require(try NumberSeriesStore(database).series(id: "fv"))
        #expect(series.series.lastCounter == 1)
        #expect(series.series.lastNumber == "FV-2026-001")
        #expect(try NumberSeriesStore(database).peekNextNumber(seriesID: "fv", on: Fixtures.day("2026-11-06")) == "FV-2026-002")

        // Frozen for the store...
        #expect(throws: DataError.documentIsFrozen(draft.id)) { try store.saveDraft(issued, now: later) }
        #expect(throws: DataError.documentAlreadyIssued(draft.id)) { try store.issue(id: draft.id, seriesID: "fv", now: later) }
        #expect(throws: DataError.documentIsFrozen(draft.id)) { try store.deleteDraft(id: draft.id, now: later) }
        // ...and for raw SQL.
        #expect(throws: DatabaseError.self) {
            try database.queue.write { db in try db.execute(sql: "UPDATE document SET number = 'X' WHERE id = ?", arguments: [draft.id]) }
        }
        #expect(throws: DatabaseError.self) {
            try database.queue.write { db in try db.execute(sql: "DELETE FROM document WHERE id = ?", arguments: [draft.id]) }
        }
        let number = try database.queue.read { db in try String.fetchOne(db, sql: "SELECT number FROM document WHERE id = ?", arguments: [draft.id]) }
        #expect(number == "FV-2026-001")

        // The stored hash is the hash of the stored snapshot.
        let row = try #require(try database.queue.read { db in
            try Row.fetchOne(db, sql: "SELECT snapshot, snapshotSHA256 FROM document WHERE id = ?", arguments: [draft.id])
        })
        let snapshot: String = row["snapshot"]
        let hash: String? = row["snapshotSHA256"]
        #expect(hash == JSONCodec.sha256(snapshot))
        #expect(hash?.count == 64)

        let events = try AuditLog(database).events(entity: "document", id: draft.id)
        #expect(events.map(\.action) == ["create", "issue"])
        #expect(events.last?.details?["number"] == "FV-2026-001")
        #expect(events.last?.details?["sha256"] == hash)
    }

    @Test func secondDocumentGetsTheNextNumberAndNumbersAreUnique() throws {
        let database = try Fixtures.prepared()
        let store = DocumentStore(database)
        try store.saveDraft(Fixtures.czkDraft(id: "a"), now: Fixtures.now)
        try store.saveDraft(Fixtures.czkDraft(id: "b"), now: Fixtures.now)
        #expect(try store.issue(id: "a", seriesID: "fv", now: Fixtures.now).number == "FV-2026-001")
        #expect(try store.issue(id: "b", seriesID: "fv", now: Fixtures.now).number == "FV-2026-002")

        // A second series producing the same text is stopped by the unique index.
        let clash = StoredNumberSeries(name: "Kolize", kinds: [],
                                       series: try DocumentNumberSeries(id: "clash", pattern: DocumentNumberPattern(template: "FV-{YYYY}-{NNN}"), year: 2026))
        try NumberSeriesStore(database).save(clash, now: Fixtures.now)
        try store.saveDraft(Fixtures.czkDraft(id: "c"), now: Fixtures.now)
        #expect(throws: DatabaseError.self) { try store.issue(id: "c", seriesID: "clash", now: Fixtures.now) }
        let still = try #require(try store.document(id: "c"))
        #expect(still.status == .draft)
        #expect(try NumberSeriesStore(database).series(id: "clash")?.series.lastCounter == 0)
    }

    @Test func failedValidationRollsEverythingBack() throws {
        let database = try Fixtures.prepared()
        let store = DocumentStore(database)
        var draft = Fixtures.czkDraft()
        draft.customer.address.street = ""
        try store.saveDraft(draft, now: Fixtures.now)

        do {
            _ = try store.issue(id: draft.id, seriesID: "fv", now: Fixtures.now)
            Issue.record("issuing an incomplete document must fail")
        } catch DataError.validationFailed(let issues) {
            #expect(issues.contains { $0.code == .customerAddressIncomplete })
            #expect(issues.allSatisfy { $0.isError })
        }
        let unchanged = try #require(try store.document(id: draft.id))
        #expect(unchanged.status == .draft)
        #expect(unchanged.number == nil)
        #expect(try NumberSeriesStore(database).series(id: "fv")?.series.lastCounter == 0)
        #expect(try AuditLog(database).events(entity: "document", id: draft.id).map(\.action) == ["create"])
        #expect(throws: DataError.seriesNotFound("missing")) { try store.issue(id: draft.id, seriesID: "missing", now: Fixtures.now) }
        #expect(throws: DataError.documentNotFound("nope")) { try store.issue(id: "nope", seriesID: "fv", now: Fixtures.now) }
    }

    @Test func eurDocumentStoresCZKEquivalents() throws {
        let database = try Fixtures.prepared()
        let store = DocumentStore(database)
        try store.saveDraft(Fixtures.eurDraft(), now: Fixtures.now)
        let issued = try store.issue(id: "doc-eu", seriesID: "fv", now: Fixtures.now)
        #expect(issued.payment?.qrCode == .sepa)
        let summary = try #require(try store.summary(id: "doc-eu"))
        #expect(summary.currency == .eur)
        #expect(summary.amountDue == Money(Fixtures.d("1000"), .eur))
        #expect(summary.taxableVATCZK == Money(0, .czk))
        let base = try database.queue.read { db in try Int64.fetchOne(db, sql: "SELECT taxableBaseCZK FROM document WHERE id = 'doc-eu'") }
        #expect(base == 2_431_000)
    }

    @Test func summariesFilter() throws {
        let database = try Fixtures.prepared()
        let store = DocumentStore(database)
        try store.saveDraft(Fixtures.czkDraft(id: "cz"), now: Fixtures.now)
        try store.saveDraft(Fixtures.eurDraft(id: "eu"), now: Fixtures.now)
        var advance = Fixtures.czkDraft(id: "adv")
        advance.kind = .advanceRequest
        advance.taxPointDate = nil
        try store.saveDraft(advance, now: Fixtures.now)
        try store.issue(id: "cz", seriesID: "fv", now: Fixtures.now)

        #expect(try store.summaries().count == 3)
        #expect(try store.summaries(DocumentFilter(kinds: [.invoice])).map(\.id).sorted() == ["cz", "eu"])
        #expect(try store.summaries(DocumentFilter(status: .issued)).map(\.id) == ["cz"])
        #expect(try store.summaries(DocumentFilter(status: .draft)).count == 2)
        #expect(try store.summaries(DocumentFilter(customerID: "cust-de")).map(\.id) == ["eu"])
        #expect(try store.summaries(DocumentFilter(year: 2026)).count == 3)
        #expect(try store.summaries(DocumentFilter(year: 2025)).isEmpty)
        #expect(try store.summaries(DocumentFilter(kinds: [.advanceRequest, .paymentTaxDocument], status: .draft)).map(\.id) == ["adv"])

        try store.deleteDraft(id: "adv", now: Fixtures.now)
        #expect(try store.summaries().count == 2)
        #expect(throws: DataError.documentNotFound("adv")) { try store.deleteDraft(id: "adv") }
    }

    @Test func paymentsAccumulate() throws {
        let database = try Fixtures.prepared()
        let store = DocumentStore(database)
        try store.saveDraft(Fixtures.czkDraft(), now: Fixtures.now)
        #expect(throws: DataError.documentNotIssued("doc-cz")) {
            try store.recordPayment(documentID: "doc-cz", on: Fixtures.day("2026-11-10"), amount: Money(Fixtures.d("5000"), .czk))
        }
        try store.issue(id: "doc-cz", seriesID: "fv", now: Fixtures.now)

        let first = try store.recordPayment(documentID: "doc-cz", on: Fixtures.day("2026-11-10"), amount: Money(Fixtures.d("5000"), .czk),
                                            note: "část", now: Fixtures.now)
        #expect(first.amount == Money(Fixtures.d("5000"), .czk))
        var state = try store.paymentState(for: "doc-cz")
        #expect(state.paid == Money(Fixtures.d("5000"), .czk))
        #expect(state.outstanding == Money(Fixtures.d("7100"), .czk))
        #expect(!state.isSettled)

        #expect(throws: DataError.currencyMismatch(expected: .czk, actual: .eur)) {
            try store.recordPayment(documentID: "doc-cz", on: Fixtures.day("2026-11-11"), amount: Money(Fixtures.d("100"), .eur))
        }
        try store.recordPayment(documentID: "doc-cz", on: Fixtures.day("2026-11-12"), amount: Money(Fixtures.d("7100"), .czk), now: Fixtures.now)
        state = try store.paymentState(for: "doc-cz")
        #expect(state.isSettled)
        #expect(state.outstanding.isZero)
        #expect(try store.payments(for: "doc-cz").map(\.paidOn) == [Fixtures.day("2026-11-10"), Fixtures.day("2026-11-12")])

        try store.deletePayment(id: first.id, now: Fixtures.now)
        #expect(try store.paymentState(for: "doc-cz").outstanding == Money(Fixtures.d("5000"), .czk))
        #expect(try AuditLog(database).events(entity: "document", id: "doc-cz").map(\.action) == ["create", "issue", "payment", "payment", "paymentDeleted"])
    }

    @Test func receiptLocksItsPayment() throws {
        let database = try Fixtures.prepared()
        let store = DocumentStore(database)
        let seriesStore = NumberSeriesStore(database)
        try seriesStore.save(StoredNumberSeries(name: "Zálohové faktury", kinds: [.advanceRequest],
                                                series: try DocumentNumberSeries(id: "zf", pattern: DocumentNumberPattern(template: "ZF-{YYYY}-{NNN}"), year: 2026)),
                             now: Fixtures.now)
        try seriesStore.save(StoredNumberSeries(name: "Doklady k platbě", kinds: [.paymentTaxDocument],
                                                series: try DocumentNumberSeries(id: "dd", pattern: DocumentNumberPattern(template: "DD-{YYYY}-{NNN}"), year: 2026)),
                             now: Fixtures.now)
        var request = Fixtures.czkDraft(id: "adv")
        request.kind = .advanceRequest
        request.taxPointDate = nil
        try store.saveDraft(request, now: Fixtures.now)
        let issuedRequest = try store.issue(id: "adv", seriesID: "zf", now: Fixtures.now)
        #expect(issuedRequest.number == "ZF-2026-001")

        let payment = try store.recordPayment(documentID: "adv", on: Fixtures.day("2026-11-10"), amount: Money(Fixtures.d("12100"), .czk), now: Fixtures.now)
        #expect(payment.receiptDocumentID == nil)
        #expect(!payment.receiptIssued)
        #expect(!payment.isFromBankImport)

        // The receipt built for the payment: linked while a draft, not yet locking.
        let receipt = Document.paymentTaxDocument(id: "dd1", forAdvanceRequest: issuedRequest, received: Fixtures.d("12100"), on: Fixtures.day("2026-11-10"))
        try store.saveDraft(receipt, now: Fixtures.now)
        let linked = try store.attachReceipt(paymentID: payment.id, documentID: "dd1", now: Fixtures.now)
        #expect(linked.receiptDocumentID == "dd1")
        #expect(!linked.receiptIssued)

        // Another amount, or another kind of document, is not this payment's receipt.
        let wrongAmount = Document.paymentTaxDocument(id: "dd2", forAdvanceRequest: issuedRequest, received: Fixtures.d("5000"), on: Fixtures.day("2026-11-10"))
        try store.saveDraft(wrongAmount, now: Fixtures.now)
        do {
            _ = try store.attachReceipt(paymentID: payment.id, documentID: "dd2", now: Fixtures.now)
            Issue.record("a receipt for another amount was accepted")
        } catch DataError.receiptMismatch(let paymentID, _) {
            #expect(paymentID == payment.id)
        }
        do {
            _ = try store.attachReceipt(paymentID: payment.id, documentID: "adv", now: Fixtures.now)
            Issue.record("an advance request was accepted as a receipt")
        } catch DataError.receiptMismatch(let paymentID, _) {
            #expect(paymentID == payment.id)
        }
        #expect(throws: DataError.paymentNotFound("nope")) { _ = try store.attachReceipt(paymentID: "nope", documentID: "dd1") }

        // Issued: the payment is locked for the store and for raw SQL alike.
        let issuedReceipt = try store.issue(id: "dd1", seriesID: "dd", now: Fixtures.now)
        #expect(issuedReceipt.number == "DD-2026-001")
        let locked = try #require(try store.payments(for: "adv").first)
        #expect(locked.receiptIssued)
        #expect(throws: DataError.paymentLocked(payment.id)) { try store.deletePayment(id: payment.id, now: Fixtures.now) }
        #expect(throws: DataError.paymentLocked(payment.id)) { _ = try store.attachReceipt(paymentID: payment.id, documentID: "dd2", now: Fixtures.now) }
        #expect(throws: DatabaseError.self) {
            try database.queue.write { db in try db.execute(sql: "DELETE FROM documentPayment WHERE id = ?", arguments: [payment.id]) }
        }
        #expect(throws: DatabaseError.self) {
            try database.queue.write { db in try db.execute(sql: "UPDATE documentPayment SET note = 'x' WHERE id = ?", arguments: [payment.id]) }
        }
        #expect(try store.paymentState(for: "adv").isSettled)

        // A draft receipt that is deleted unlinks itself from its payment, which stays deletable.
        let second = try store.recordPayment(documentID: "adv", on: Fixtures.day("2026-11-11"), amount: Money(Fixtures.d("5000"), .czk), now: Fixtures.now)
        _ = try store.attachReceipt(paymentID: second.id, documentID: "dd2", now: Fixtures.now)
        try store.deleteDraft(id: "dd2", now: Fixtures.now)
        #expect(try store.payments(for: "adv").last?.receiptDocumentID == nil)
        try store.deletePayment(id: second.id, now: Fixtures.now)
        #expect(try AuditLog(database).events(entity: "document", id: "adv").map(\.action)
                == ["create", "issue", "payment", "receiptAttached", "payment", "receiptAttached", "paymentDeleted"])
    }
}
