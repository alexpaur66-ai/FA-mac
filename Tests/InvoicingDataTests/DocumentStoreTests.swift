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
        #expect(summary.updatedAt == "2026-11-05T05:00:00Z")
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
        try store.saveDraft(Document.paymentTaxDocument(id: "dd4", forAdvanceRequest: issuedRequest, received: Fixtures.d("5000"), on: Fixtures.day("2026-11-11")),
                            now: Fixtures.now)
        _ = try store.attachReceipt(paymentID: second.id, documentID: "dd4", now: Fixtures.now)
        try store.deleteDraft(id: "dd4", now: Fixtures.now)
        #expect(try store.payments(for: "adv").last?.receiptDocumentID == nil)
        try store.deletePayment(id: second.id, now: Fixtures.now)
        #expect(try AuditLog(database).events(entity: "document", id: "adv").map(\.action)
                == ["create", "issue", "payment", "receiptAttached", "payment", "receiptAttached", "paymentDeleted"])
    }

    @Test func linkedReceiptCannotDriftFromItsPayment() throws {
        let database = try Fixtures.prepared()
        let store = DocumentStore(database)
        try Fixtures.addAdvanceSeries(database)
        let request = try Fixtures.issuedAdvance(database)
        let payment = try store.recordPayment(documentID: "adv", on: Fixtures.day("2026-11-10"), amount: Money(Fixtures.d("12100"), .czk), now: Fixtures.now)
        let receipt = Document.paymentTaxDocument(id: "dd1", forAdvanceRequest: request, received: Fixtures.d("12100"), on: Fixtures.day("2026-11-10"))
        try store.saveDraft(receipt, now: Fixtures.now)
        _ = try store.attachReceipt(paymentID: payment.id, documentID: "dd1", now: Fixtures.now)

        // Saving the linked draft with another amount, kind or currency is refused; the draft stays as it was.
        let smaller = Document.paymentTaxDocument(id: "dd1", forAdvanceRequest: request, received: Fixtures.d("5000"), on: Fixtures.day("2026-11-10"))
        do {
            try store.saveDraft(smaller, now: Fixtures.now)
            Issue.record("a linked receipt was saved for another amount")
        } catch DataError.receiptMismatch(let paymentID, _) {
            #expect(paymentID == payment.id)
        }
        var invoice = receipt
        invoice.kind = .invoice
        do {
            try store.saveDraft(invoice, now: Fixtures.now)
            Issue.record("a linked receipt was saved as an invoice")
        } catch DataError.receiptMismatch(let paymentID, _) {
            #expect(paymentID == payment.id)
        }
        var euros = receipt
        euros.currency = .eur
        #expect(throws: DataError.currencyMismatch(expected: .czk, actual: .eur)) { try store.saveDraft(euros, now: Fixtures.now) }
        #expect(try store.document(id: "dd1") == receipt)

        // A drifted row that got past saveDraft (here written directly, without amounts, so attaching it
        // skips the amount check) is caught when it is issued: nothing is numbered, frozen or locked.
        let drifted = try DocumentRecord(document: smaller, totals: nil, createdAt: "2026-11-05T05:00:00Z", updatedAt: "2026-11-05T05:00:00Z", issuedAt: nil)
        try database.queue.write { db in try drifted.update(db) }
        _ = try store.attachReceipt(paymentID: payment.id, documentID: "dd1", now: Fixtures.now)
        do {
            _ = try store.issue(id: "dd1", seriesID: "dd", now: Fixtures.now)
            Issue.record("a receipt for another amount than its payment was issued")
        } catch DataError.receiptMismatch(let paymentID, _) {
            #expect(paymentID == payment.id)
        }
        let still = try #require(try store.document(id: "dd1"))
        #expect(still.status == .draft)
        #expect(still.number == nil)
        #expect(try NumberSeriesStore(database).series(id: "dd")?.series.lastCounter == 0)
        #expect(try store.payments(for: "adv").first?.receiptIssued == false)
        #expect(try AuditLog(database).events(entity: "document", id: "dd1").map { $0.action } == ["create"])

        // The matching receipt issues and locks its payment.
        try store.saveDraft(receipt, now: Fixtures.now)
        #expect(try store.issue(id: "dd1", seriesID: "dd", now: Fixtures.now).number == "DD-2026-001")
        #expect(try store.payments(for: "adv").first?.receiptIssued == true)
    }

    @Test func aReceiptStatesTheDayItsPaymentWasReceived() throws {
        let database = try Fixtures.prepared()
        let store = DocumentStore(database)
        try Fixtures.addAdvanceSeries(database)
        let request = try Fixtures.issuedAdvance(database)
        let payment = try store.recordPayment(documentID: "adv", on: Fixtures.day("2026-11-10"), amount: Money(Fixtures.d("12100"), .czk), now: Fixtures.now)

        // § 29 odst. 1 písm. h) ZDPH: the tax point of the payment tax document is the day of the payment.
        var moved = Document.paymentTaxDocument(id: "dd1", forAdvanceRequest: request, received: Fixtures.d("12100"), on: Fixtures.day("2026-11-10"))
        moved.taxPointDate = Fixtures.day("2026-11-12")
        try store.saveDraft(moved, now: Fixtures.now)
        do {
            _ = try store.attachReceipt(paymentID: payment.id, documentID: "dd1", now: Fixtures.now)
            Issue.record("a receipt dated on another day than its payment was accepted")
        } catch DataError.receiptMismatch(let paymentID, _) {
            #expect(paymentID == payment.id)
        }
        #expect(try store.payments(for: "adv").first?.receiptDocumentID == nil)

        // Linked with the payment's day, the draft cannot move its tax point afterwards.
        let receipt = Document.paymentTaxDocument(id: "dd1", forAdvanceRequest: request, received: Fixtures.d("12100"), on: Fixtures.day("2026-11-10"))
        try store.saveDraft(receipt, now: Fixtures.now)
        #expect(try store.attachReceipt(paymentID: payment.id, documentID: "dd1", now: Fixtures.now).receiptDocumentID == "dd1")
        do {
            try store.saveDraft(moved, now: Fixtures.now)
            Issue.record("a linked receipt moved its tax point off the payment date")
        } catch DataError.receiptMismatch(let paymentID, _) {
            #expect(paymentID == payment.id)
        }
        #expect(try store.document(id: "dd1")?.taxPointDate == Fixtures.day("2026-11-10"))
        try store.issue(id: "dd1", seriesID: "dd", now: Fixtures.now)
    }

    @Test func aReceiptBelongsToOnePayment() throws {
        let database = try Fixtures.prepared()
        let store = DocumentStore(database)
        try Fixtures.addAdvanceSeries(database)
        let request = try Fixtures.issuedAdvance(database)
        let first = try store.recordPayment(documentID: "adv", on: Fixtures.day("2026-11-10"), amount: Money(Fixtures.d("12100"), .czk), now: Fixtures.now)
        let second = try store.recordPayment(documentID: "adv", on: Fixtures.day("2026-11-10"), amount: Money(Fixtures.d("12100"), .czk), now: Fixtures.now)
        let receipt = Document.paymentTaxDocument(id: "dd1", forAdvanceRequest: request, received: Fixtures.d("12100"), on: Fixtures.day("2026-11-10"))
        try store.saveDraft(receipt, now: Fixtures.now)
        _ = try store.attachReceipt(paymentID: first.id, documentID: "dd1", now: Fixtures.now)
        // Attaching it again to the same payment is harmless.
        _ = try store.attachReceipt(paymentID: first.id, documentID: "dd1", now: Fixtures.now)

        do {
            _ = try store.attachReceipt(paymentID: second.id, documentID: "dd1", now: Fixtures.now)
            Issue.record("one receipt was attached to two payments")
        } catch DataError.receiptMismatch(let paymentID, _) {
            #expect(paymentID == second.id)
        }
        try store.issue(id: "dd1", seriesID: "dd", now: Fixtures.now)
        do {
            _ = try store.attachReceipt(paymentID: second.id, documentID: "dd1", now: Fixtures.now)
            Issue.record("an issued receipt was attached to a second payment")
        } catch DataError.receiptMismatch(let paymentID, _) {
            #expect(paymentID == second.id)
        }
        let payments = try store.payments(for: "adv")
        #expect(payments.first { $0.id == first.id }?.receiptIssued == true)
        let other = try #require(payments.first { $0.id == second.id })
        #expect(other.receiptDocumentID == nil)
        #expect(!other.receiptIssued)
        // The second payment is not locked and can still be removed.
        try store.deletePayment(id: second.id, now: Fixtures.now)
        #expect(try store.payments(for: "adv").map { $0.id } == [first.id])
    }

    @Test func aReceiptIsForTheAdvanceThePaymentWasReceivedOn() throws {
        let database = try Fixtures.prepared()
        let store = DocumentStore(database)
        try Fixtures.addAdvanceSeries(database)
        let firstRequest = try Fixtures.issuedAdvance(database, id: "adv")
        let secondRequest = try Fixtures.issuedAdvance(database, id: "adv2")
        #expect(secondRequest.number == "ZF-2026-002")
        let onFirst = try store.recordPayment(documentID: "adv", on: Fixtures.day("2026-11-10"), amount: Money(Fixtures.d("12100"), .czk), now: Fixtures.now)
        let onSecond = try store.recordPayment(documentID: "adv2", on: Fixtures.day("2026-11-10"), amount: Money(Fixtures.d("12100"), .czk), now: Fixtures.now)

        // A receipt naming the second advance is not the receipt of a payment on the first.
        let forSecond = Document.paymentTaxDocument(id: "dd2", forAdvanceRequest: secondRequest, received: Fixtures.d("12100"), on: Fixtures.day("2026-11-10"))
        try store.saveDraft(forSecond, now: Fixtures.now)
        do {
            _ = try store.attachReceipt(paymentID: onFirst.id, documentID: "dd2", now: Fixtures.now)
            Issue.record("a receipt for another advance was accepted")
        } catch DataError.receiptMismatch(let paymentID, _) {
            #expect(paymentID == onFirst.id)
        }
        #expect(try store.attachReceipt(paymentID: onSecond.id, documentID: "dd2", now: Fixtures.now).receiptDocumentID == "dd2")

        // A receipt for another customer is refused.
        var otherCustomer = Document.paymentTaxDocument(id: "dd3", forAdvanceRequest: firstRequest, received: Fixtures.d("12100"), on: Fixtures.day("2026-11-10"))
        otherCustomer.customerID = "cust-de"
        otherCustomer.customer = Fixtures.germanParty
        try store.saveDraft(otherCustomer, now: Fixtures.now)
        do {
            _ = try store.attachReceipt(paymentID: onFirst.id, documentID: "dd3", now: Fixtures.now)
            Issue.record("a receipt for another customer was accepted")
        } catch DataError.receiptMismatch(let paymentID, _) {
            #expect(paymentID == onFirst.id)
        }

        // A payment of an ordinary invoice takes no payment tax document.
        try store.saveDraft(Fixtures.czkDraft(), now: Fixtures.now)
        try store.issue(id: "doc-cz", seriesID: "fv", now: Fixtures.now)
        let invoicePayment = try store.recordPayment(documentID: "doc-cz", on: Fixtures.day("2026-11-10"), amount: Money(Fixtures.d("12100"), .czk), now: Fixtures.now)
        let forFirst = Document.paymentTaxDocument(id: "dd1", forAdvanceRequest: firstRequest, received: Fixtures.d("12100"), on: Fixtures.day("2026-11-10"))
        try store.saveDraft(forFirst, now: Fixtures.now)
        do {
            _ = try store.attachReceipt(paymentID: invoicePayment.id, documentID: "dd1", now: Fixtures.now)
            Issue.record("a payment tax document was attached to an invoice payment")
        } catch DataError.receiptMismatch(let paymentID, _) {
            #expect(paymentID == invoicePayment.id)
        }
        #expect(try store.payments(for: "doc-cz").first?.receiptDocumentID == nil)
        #expect(try store.attachReceipt(paymentID: onFirst.id, documentID: "dd1", now: Fixtures.now).receiptDocumentID == "dd1")
    }

    @Test func issueRefusesASeriesForAnotherKind() throws {
        let database = try Fixtures.prepared()
        let store = DocumentStore(database)
        try Fixtures.addAdvanceSeries(database)
        try store.saveDraft(Fixtures.czkDraft(), now: Fixtures.now)
        #expect(throws: DataError.seriesDoesNotNumber(seriesID: "zf", kind: .invoice)) {
            try store.issue(id: "doc-cz", seriesID: "zf", now: Fixtures.now)
        }
        let unchanged = try #require(try store.document(id: "doc-cz"))
        #expect(unchanged.status == .draft)
        #expect(unchanged.number == nil)
        #expect(try NumberSeriesStore(database).series(id: "zf")?.series.lastCounter == 0)
        #expect(try AuditLog(database).events(entity: "document", id: "doc-cz").map { $0.action } == ["create"])

        var request = Fixtures.czkDraft(id: "adv")
        request.kind = .advanceRequest
        request.taxPointDate = nil
        try store.saveDraft(request, now: Fixtures.now)
        #expect(throws: DataError.seriesDoesNotNumber(seriesID: "fv", kind: .advanceRequest)) {
            try store.issue(id: "adv", seriesID: "fv", now: Fixtures.now)
        }
        #expect(try NumberSeriesStore(database).series(id: "fv")?.series.lastCounter == 0)

        // A series with no kinds numbers any kind.
        let anyKind = StoredNumberSeries(name: "Vše", kinds: [],
                                     series: try DocumentNumberSeries(id: "any", pattern: DocumentNumberPattern(template: "X-{YYYY}-{NNN}"), year: 2026))
        try NumberSeriesStore(database).save(anyKind, now: Fixtures.now)
        #expect(try store.issue(id: "doc-cz", seriesID: "any", now: Fixtures.now).number == "X-2026-001")
    }

    @Test func variableSymbolFollowsTheSeriesPrefix() throws {
        let database = try Fixtures.prepared()
        try NumberSeriesStore(database).save(try Fixtures.invoiceSeries(variableSymbolPrefix: "1"), now: Fixtures.now)
        let store = DocumentStore(database)
        try store.saveDraft(Fixtures.czkDraft(), now: Fixtures.now)
        let issued = try store.issue(id: "doc-cz", seriesID: "fv", now: Fixtures.now)
        #expect(issued.number == "FV-2026-001")
        #expect(issued.payment?.variableSymbol?.digits == "12026001")
        #expect(try store.summary(id: "doc-cz")?.variableSymbol == "12026001")
        // A draft that brought its own symbol keeps it.
        var own = Fixtures.czkDraft(id: "doc-2")
        own.payment = PaymentInstructions(bankConnection: Fixtures.bank, variableSymbol: PaymentSymbol.variable("777"))
        try store.saveDraft(own, now: Fixtures.now)
        #expect(try store.issue(id: "doc-2", seriesID: "fv", now: Fixtures.now).payment?.variableSymbol?.digits == "777")
    }

    @Test func refundsAndAppliedCreditMoveTheBalance() throws {
        let database = try Fixtures.prepared()
        let store = DocumentStore(database)
        try store.saveDraft(Fixtures.czkDraft(), now: Fixtures.now)
        try store.saveDraft(Fixtures.czkDraft(id: "doc-2"), now: Fixtures.now)
        try store.issue(id: "doc-cz", seriesID: "fv", now: Fixtures.now)
        try store.issue(id: "doc-2", seriesID: "fv", now: Fixtures.now)
        func czk(_ text: String) -> Money { Money(Fixtures.d(text), .czk) }
        let day = Fixtures.day("2026-11-10")

        // Overpaid by 1 000 CZK; zero and negative payments are refused.
        try store.recordPayment(documentID: "doc-cz", on: day, amount: czk("13100"), now: Fixtures.now)
        #expect(try store.paymentState(for: "doc-cz").outstanding == czk("-1000"))
        #expect(throws: DataError.invalidPaymentAmount(czk("0"))) {
            try store.recordPayment(documentID: "doc-cz", on: day, amount: czk("0"), now: Fixtures.now)
        }
        #expect(throws: DataError.invalidPaymentAmount(czk("-5"))) {
            try store.recordPayment(documentID: "doc-cz", on: day, amount: czk("-5"), now: Fixtures.now)
        }

        // 400 CZK paid back: a negative refund row.
        let refund = try store.recordRefund(documentID: "doc-cz", on: day, amount: czk("400"), now: Fixtures.now)
        #expect(refund.kind == .refund)
        #expect(refund.amount == czk("-400"))
        #expect(!refund.isIncoming)
        #expect(try store.paymentState(for: "doc-cz").outstanding == czk("-600"))
        #expect(throws: DataError.invalidPaymentAmount(czk("5"))) {
            try store.recordRefund(documentID: "doc-cz", on: day, amount: czk("-5"), now: Fixtures.now)
        }

        // The remaining 600 CZK credit goes to the second invoice; more than that is refused.
        #expect(throws: DataError.creditNotAvailable(sourceDocumentID: "doc-cz", available: czk("600"), requested: czk("601"))) {
            try store.applyCredit(from: "doc-cz", to: "doc-2", amount: czk("601"), on: day, now: Fixtures.now)
        }
        let credit = try store.applyCredit(from: "doc-cz", to: "doc-2", amount: czk("600"), on: day, now: Fixtures.now)
        #expect(credit.kind == .creditIn)
        #expect(credit.documentID == "doc-2")
        #expect(credit.amount == czk("600"))
        #expect(try store.paymentState(for: "doc-cz").outstanding == czk("0"))
        #expect(try store.paymentState(for: "doc-2").outstanding == czk("11500"))
        let out = try #require(try store.payments(for: "doc-cz").first { $0.kind == .creditOut })
        #expect(out.amount == czk("-600"))
        #expect(out.relatedPaymentID == credit.id)
        #expect(credit.relatedPaymentID == out.id)

        // A document without credit gives none; a credit never overpays its target.
        #expect(throws: DataError.creditNotAvailable(sourceDocumentID: "doc-cz", available: czk("0"), requested: czk("1"))) {
            try store.applyCredit(from: "doc-cz", to: "doc-2", amount: czk("1"), on: day, now: Fixtures.now)
        }
        try store.recordPayment(documentID: "doc-2", on: day, amount: czk("12000"), now: Fixtures.now)
        #expect(throws: DataError.creditExceedsOutstanding(targetDocumentID: "doc-cz", outstanding: czk("0"), requested: czk("500"))) {
            try store.applyCredit(from: "doc-2", to: "doc-cz", amount: czk("500"), on: day, now: Fixtures.now)
        }

        // Deleting one leg deletes the other.
        try store.deletePayment(id: credit.id, now: Fixtures.now)
        let sourceKinds = try store.payments(for: "doc-cz").map { $0.kind.rawValue }.sorted()
        let targetKinds = try store.payments(for: "doc-2").map { $0.kind.rawValue }
        #expect(sourceKinds == ["received", "refund"])
        #expect(targetKinds == ["received"])
        #expect(try store.paymentState(for: "doc-cz").outstanding == czk("-600"))
        #expect(try store.paymentState(for: "doc-2").outstanding == czk("100"))
    }

    @Test func statesFollowPaymentsClosuresAndTime() throws {
        let database = try Fixtures.prepared()
        try Fixtures.addAdvanceSeries(database)
        let store = DocumentStore(database)
        let due = Fixtures.day("2026-11-19")
        func czk(_ text: String) -> Money { Money(Fixtures.d(text), .czk) }

        try store.saveDraft(Fixtures.czkDraft(), now: Fixtures.now)
        #expect(try store.state(for: "doc-cz", today: due).settlement == .draft)

        try store.issue(id: "doc-cz", seriesID: "fv", now: Fixtures.now)
        var state = try store.state(for: "doc-cz", today: due)
        #expect(state.settlement == .open)
        #expect(!state.isOverdue)
        #expect(state.outstanding == czk("12100"))
        state = try store.state(for: "doc-cz", today: due.adding(days: 12))
        #expect(state.isOverdue)
        #expect(state.daysOverdue == 12)

        try store.recordPayment(documentID: "doc-cz", on: due, amount: czk("100"), now: Fixtures.now)
        state = try store.state(for: "doc-cz", today: due.adding(days: 1))
        #expect(state.settlement == .partlyPaid)
        #expect(state.isOverdue)
        #expect(state.paid == czk("100"))
        try store.recordPayment(documentID: "doc-cz", on: due, amount: czk("12000"), now: Fixtures.now)
        state = try store.state(for: "doc-cz", today: due.adding(days: 1))
        #expect(state.settlement == .paid)
        #expect(!state.isOverdue)
        try store.recordPayment(documentID: "doc-cz", on: due, amount: czk("1"), now: Fixtures.now)
        #expect(try store.state(for: "doc-cz", today: due).settlement == .overpaid)

        // Marked for a credit note: a fact beside the settlement, and never overdue.
        try store.saveDraft(Fixtures.czkDraft(id: "doc-2"), now: Fixtures.now)
        try store.issue(id: "doc-2", seriesID: "fv", now: Fixtures.now)
        try store.markForCreditNote(id: "doc-2", reason: "wrong customer", now: Fixtures.now)
        state = try store.state(for: "doc-2", today: due.adding(days: 30))
        #expect(state.settlement == .open)
        #expect(state.markedForCreditNote)
        #expect(!state.isOverdue)
        #expect(state.closure?.reason == "wrong customer")
        try store.reopen(id: "doc-2", now: Fixtures.now)
        #expect(try store.state(for: "doc-2", today: due.adding(days: 30)).isOverdue)

        // An advance: open and overdue, paid without its tax document, then with it; a receipt is paid by definition.
        let advance = try Fixtures.issuedAdvance(database)
        state = try store.state(for: advance.id, today: due.adding(days: 1))
        #expect(state.settlement == .open)
        #expect(state.isOverdue)
        #expect(!state.taxDocumentIssued)
        #expect(state.taxDocumentRequired)
        let receipt = try Fixtures.issuedReceipt(database, advance: advance)
        state = try store.state(for: advance.id, today: due.adding(days: 1))
        #expect(state.settlement == .paid)
        #expect(state.taxDocumentIssued)
        #expect(!state.deductedInFinal)
        let receiptState = try store.state(for: receipt.id, today: due.adding(days: 100))
        #expect(receiptState.settlement == .paid)
        #expect(!receiptState.isOverdue)
        // Paid in full by definition: the payment is booked on the advance, nothing is outstanding on the receipt.
        #expect(receiptState.paid == czk("12100"))
        #expect(receiptState.outstanding == czk("0"))
        // A further payment without its receipt turns the flag off again.
        try store.recordPayment(documentID: advance.id, on: due, amount: czk("500"), now: Fixtures.now)
        state = try store.state(for: advance.id, today: due)
        #expect(state.settlement == .overpaid)
        #expect(!state.taxDocumentIssued)

        // Lists come in the summaries' order.
        let listed = try store.states(today: due).map { $0.id }
        let summarised = try store.summaries().map { $0.id }
        #expect(listed == summarised)
        #expect(listed.count == 4)
        let advances = try store.states(DocumentFilter(kinds: [.advanceRequest]), today: due).map { $0.id }
        #expect(advances == [advance.id])
    }

    @Test func statesCanBeObserved() async throws {
        let database = try Fixtures.prepared()
        let store = DocumentStore(database)
        try store.saveDraft(Fixtures.czkDraft(), now: Fixtures.now)
        var first: [DocumentState] = []
        for try await states in store.observeStates(today: Fixtures.day("2026-11-05")).values(in: database.queue) {
            first = states
            break
        }
        let ids = first.map { $0.id }
        #expect(ids == ["doc-cz"])
        #expect(first.first?.settlement == .draft)

        // A payment written after the subscription delivers a new value.
        try store.issue(id: "doc-cz", seriesID: "fv", now: Fixtures.now)
        var received: [[DocumentState]] = []
        for try await states in store.observeStates(today: Fixtures.day("2026-11-05")).values(in: database.queue) {
            received.append(states)
            if received.count == 1 {
                try store.recordPayment(documentID: "doc-cz", on: Fixtures.day("2026-11-05"), amount: Money(100, .czk), now: Fixtures.now)
            } else if states.first?.settlement == .partlyPaid || received.count >= 5 {
                break
            }
        }
        #expect(received.first?.first?.settlement == .open)
        let last = try #require(received.last?.first)
        #expect(received.count >= 2)
        #expect(last.settlement == .partlyPaid)
        #expect(last.paid == Money(100, .czk))
    }

    @Test func finalInvoiceLinksTheReceiptsItDeducts() throws {
        let database = try Fixtures.prepared()
        try Fixtures.addAdvanceSeries(database)
        let store = DocumentStore(database)
        let advance = try Fixtures.issuedAdvance(database)
        let receipt = try Fixtures.issuedReceipt(database, advance: advance)
        let due = Fixtures.day("2026-11-19")

        try store.saveDraft(try Fixtures.finalInvoiceDraft(deducting: receipt), now: Fixtures.now)
        let finalInvoice = try store.issue(id: "final", seriesID: "fv", now: Fixtures.now)
        #expect(finalInvoice.number == "FV-2026-001")
        let links = try store.deductions(ofFinalInvoice: "final")
        #expect(links.count == 1)
        #expect(links.first?.receiptDocumentID == receipt.id)
        #expect(links.first?.receiptNumber == "DD-2026-001")
        #expect(links.first?.advanceRequestID == advance.id)
        #expect(links.first?.finalInvoiceNumber == "FV-2026-001")
        #expect(try store.deduction(ofReceipt: receipt.id)?.finalInvoiceID == "final")
        #expect(try store.deductions(ofAdvanceRequest: advance.id).count == 1)

        // The advance is settled in the final invoice; the final invoice is settled by its advances.
        let advanceState = try store.state(for: advance.id, today: due.adding(days: 30))
        #expect(advanceState.deductedInFinal)
        #expect(advanceState.deductedBy == ["FV-2026-001"])
        #expect(!advanceState.isOverdue)
        let finalState = try store.state(for: "final", today: due.adding(days: 30))
        #expect(finalState.settlement == .settledByAdvances)
        #expect(finalState.outstanding == Money(0, .czk))
        #expect(!finalState.isOverdue)

        // The same receipt cannot be deducted by a second final invoice, and the number is not consumed.
        try store.saveDraft(try Fixtures.finalInvoiceDraft(id: "final-2", deducting: receipt), now: Fixtures.now)
        #expect(throws: DataError.advanceAlreadyDeducted(receiptNumber: "DD-2026-001", by: "FV-2026-001")) {
            try store.issue(id: "final-2", seriesID: "fv", now: Fixtures.now)
        }
        #expect(try store.summary(id: "final-2")?.status == .draft)
        #expect(try NumberSeriesStore(database).peekNextNumber(seriesID: "fv", on: due) == "FV-2026-002")

        // A receipt issued before the app (a number the database does not know) is deducted without a link.
        var external = try Fixtures.finalInvoiceDraft(id: "final-3", deducting: receipt)
        external.advanceDeductions = external.advanceDeductions.map {
            AdvanceDeduction(documentNumber: "DD-2025-099", paymentDate: $0.paymentDate, treatment: $0.treatment, ratePercent: $0.ratePercent,
                             base: $0.base, vat: $0.vat, currency: $0.currency, exchangeRate: $0.exchangeRate)
        }
        try store.saveDraft(external, now: Fixtures.now)
        try store.issue(id: "final-3", seriesID: "fv", now: Fixtures.now)
        #expect(try store.deductions(ofFinalInvoice: "final-3").isEmpty)
        let events = try AuditLog(database).events(entity: "document", id: "final-3")
        #expect(events.last?.action == "issue")
        #expect(events.last?.details?["externalDeductions"] == "DD-2025-099")

        // The links are frozen like the final invoice; an advance with payments cannot be closed as unpaid.
        #expect(throws: DatabaseError.self) {
            try database.queue.write { db in try db.execute(sql: "DELETE FROM advanceDeduction") }
        }
        #expect(throws: DataError.documentHasPayments(advance.id)) {
            try store.closeAdvanceUnpaid(id: advance.id, reason: "x", now: Fixtures.now)
        }
        #expect(try store.verifyIntegrity(id: "final"))
        #expect(throws: DataError.documentNotIssued("final-2")) { try store.verifyIntegrity(id: "final-2") }
    }

    @Test func verifyIntegrityDetectsAChangedSnapshotOrHash() throws {
        let database = try Fixtures.prepared()
        let store = DocumentStore(database)
        try store.saveDraft(Fixtures.czkDraft(), now: Fixtures.now)
        try store.issue(id: "doc-cz", seriesID: "fv", now: Fixtures.now)
        #expect(try store.verifyIntegrity(id: "doc-cz"))

        // Tampering needs the frozen trigger gone, which only this test database allows.
        try database.queue.write { db in
            try db.execute(sql: "DROP TRIGGER document_frozen_update")
            try db.execute(sql: "UPDATE document SET snapshot = replace(snapshot, 'Konzultace', 'Konzultace!') WHERE id = ?", arguments: ["doc-cz"])
        }
        #expect(try store.verifyIntegrity(id: "doc-cz") == false)

        // The snapshot restored is whole again; a changed hash is caught as well.
        try database.queue.write { db in
            try db.execute(sql: "UPDATE document SET snapshot = replace(snapshot, 'Konzultace!', 'Konzultace') WHERE id = ?", arguments: ["doc-cz"])
        }
        #expect(try store.verifyIntegrity(id: "doc-cz"))
        try database.queue.write { db in
            try db.execute(sql: "UPDATE document SET snapshotSHA256 = ? WHERE id = ?", arguments: [String(repeating: "0", count: 64), "doc-cz"])
        }
        #expect(try store.verifyIntegrity(id: "doc-cz") == false)
    }

    @Test func closingEventsHaveRules() throws {
        let database = try Fixtures.prepared()
        try Fixtures.addAdvanceSeries(database)
        let store = DocumentStore(database)
        try store.saveDraft(Fixtures.czkDraft(), now: Fixtures.now)
        #expect(throws: DataError.documentNotIssued("doc-cz")) {
            try store.markForCreditNote(id: "doc-cz", reason: "typo", now: Fixtures.now)
        }
        try store.issue(id: "doc-cz", seriesID: "fv", now: Fixtures.now)
        #expect(throws: DataError.closureNotApplicable(id: "doc-cz", kind: .invoice)) {
            try store.closeAdvanceUnpaid(id: "doc-cz", reason: "never paid", now: Fixtures.now)
        }
        #expect(throws: DataError.reasonRequired) {
            try store.markForCreditNote(id: "doc-cz", reason: "  ", now: Fixtures.now)
        }
        try store.markForCreditNote(id: "doc-cz", reason: "typo", now: Fixtures.now)
        #expect(throws: DataError.documentAlreadyClosed("doc-cz")) {
            try store.markForCreditNote(id: "doc-cz", reason: "again", now: Fixtures.now)
        }
        #expect(try store.closure(for: "doc-cz")?.kind == .markedForCreditNote)

        let advance = try Fixtures.issuedAdvance(database)
        #expect(throws: DataError.closureNotApplicable(id: advance.id, kind: .advanceRequest)) {
            try store.markForCreditNote(id: advance.id, reason: "x", now: Fixtures.now)
        }
        try store.closeAdvanceUnpaid(id: advance.id, reason: "scope dropped", now: Fixtures.now)
        let state = try store.state(for: advance.id, today: Fixtures.day("2027-01-01"))
        #expect(state.settlement == .closedUnpaid)
        #expect(!state.isOverdue)
        #expect(state.closure?.kind == .closedUnpaid)
        // A closed advance takes no payment until it is reopened.
        #expect(throws: DataError.documentAlreadyClosed(advance.id)) {
            try store.recordPayment(documentID: advance.id, on: Fixtures.day("2026-12-01"), amount: Money(1, .czk), now: Fixtures.now)
        }
        try store.reopen(id: advance.id, now: Fixtures.now)
        #expect(try store.closure(for: advance.id) == nil)
        #expect(throws: DataError.documentNotClosed(advance.id)) { try store.reopen(id: advance.id, now: Fixtures.now) }
        try store.recordPayment(documentID: advance.id, on: Fixtures.day("2026-12-01"), amount: Money(1, .czk), now: Fixtures.now)
        let actions = try AuditLog(database).events(entity: "document", id: advance.id).map { $0.action }
        #expect(actions.suffix(3) == ["close", "reopen", "payment"])
    }

    @Test func refundsAreBoundedByWhatTheDocumentHolds() throws {
        let database = try Fixtures.prepared()
        try Fixtures.addAdvanceSeries(database)
        let store = DocumentStore(database)
        func czk(_ text: String) -> Money { Money(Fixtures.d(text), .czk) }
        let day = Fixtures.day("2026-11-10")
        try store.saveDraft(Fixtures.czkDraft(), now: Fixtures.now)
        try store.saveDraft(Fixtures.czkDraft(id: "doc-2"), now: Fixtures.now)
        try store.issue(id: "doc-cz", seriesID: "fv", now: Fixtures.now)
        try store.issue(id: "doc-2", seriesID: "fv", now: Fixtures.now)

        // Nothing received: nothing to pay back, and no row is written.
        #expect(throws: DataError.refundExceedsAvailable(documentID: "doc-2", available: czk("0"), requested: czk("1"))) {
            try store.recordRefund(documentID: "doc-2", on: day, amount: czk("1"), now: Fixtures.now)
        }
        #expect(try store.payments(for: "doc-2").isEmpty)
        #expect(try store.paymentState(for: "doc-2").paid == czk("0"))

        // Overpaid by 1 000 CZK: the net paid amount may go back (an order cancelled), not more.
        try store.recordPayment(documentID: "doc-cz", on: day, amount: czk("13100"), now: Fixtures.now)
        #expect(throws: DataError.refundExceedsAvailable(documentID: "doc-cz", available: czk("13100"), requested: czk("13101"))) {
            try store.recordRefund(documentID: "doc-cz", on: day, amount: czk("13101"), now: Fixtures.now)
        }
        try store.recordRefund(documentID: "doc-cz", on: day, amount: czk("13100"), now: Fixtures.now)
        let refunded = try store.state(for: "doc-cz", today: day)
        #expect(refunded.paid == czk("0"))
        #expect(refunded.outstanding == czk("12100"))
        #expect(refunded.settlement == .open)
        #expect(throws: DataError.refundExceedsAvailable(documentID: "doc-cz", available: czk("0"), requested: czk("1"))) {
            try store.recordRefund(documentID: "doc-cz", on: day, amount: czk("1"), now: Fixtures.now)
        }

        // A final invoice whose advances exceed the supply: the customer's credit may go back, not more.
        let advance = try Fixtures.issuedAdvance(database)
        let receipt = try Fixtures.issuedReceipt(database, advance: advance)
        var draft = try Fixtures.finalInvoiceDraft(deducting: receipt)
        draft.lines[0].quantity = 5
        try store.saveDraft(draft, now: Fixtures.now)
        try store.issue(id: "final", seriesID: "fv", now: Fixtures.now)
        #expect(try store.paymentState(for: "final").amountDue == czk("-6050"))
        #expect(throws: DataError.refundExceedsAvailable(documentID: "final", available: czk("6050"), requested: czk("6050.01"))) {
            try store.recordRefund(documentID: "final", on: day, amount: czk("6050.01"), now: Fixtures.now)
        }
        try store.recordRefund(documentID: "final", on: day, amount: czk("6050"), now: Fixtures.now)
        let finalState = try store.state(for: "final", today: day)
        #expect(finalState.paid == czk("-6050"))
        #expect(finalState.outstanding == czk("0"))
        #expect(finalState.settlement == .paid)
        #expect(!finalState.isOverdue)
    }

    @Test func aPaymentTaxDocumentTakesNoPayments() throws {
        let database = try Fixtures.prepared()
        try Fixtures.addAdvanceSeries(database)
        let store = DocumentStore(database)
        func czk(_ text: String) -> Money { Money(Fixtures.d(text), .czk) }
        let day = Fixtures.day("2026-11-10")
        let advance = try Fixtures.issuedAdvance(database)
        let receipt = try Fixtures.issuedReceipt(database, advance: advance)

        #expect(throws: DataError.documentNotPayable(receipt.id)) {
            try store.recordPayment(documentID: receipt.id, on: day, amount: czk("3000"), now: Fixtures.now)
        }
        #expect(throws: DataError.documentNotPayable(receipt.id)) {
            try store.recordRefund(documentID: receipt.id, on: day, amount: czk("1"), now: Fixtures.now)
        }
        // Credit from an overpaid invoice of the same customer is not moved to the receipt either; both legs roll back.
        try store.saveDraft(Fixtures.czkDraft(), now: Fixtures.now)
        try store.issue(id: "doc-cz", seriesID: "fv", now: Fixtures.now)
        try store.recordPayment(documentID: "doc-cz", on: day, amount: czk("13100"), now: Fixtures.now)
        #expect(throws: DataError.documentNotPayable(receipt.id)) {
            try store.applyCredit(from: "doc-cz", to: receipt.id, amount: czk("500"), on: day, now: Fixtures.now)
        }
        #expect(try store.payments(for: receipt.id).isEmpty)
        #expect(try store.payments(for: "doc-cz").map { $0.kind } == [.received])
        #expect(try store.paymentState(for: "doc-cz").outstanding == czk("-1000"))
    }

    @Test func creditMovesOnlyWithinOneCustomer() throws {
        let database = try Fixtures.prepared()
        try CustomerStore(database).save(Fixtures.czechCustomer(id: "cust-cz2"), now: Fixtures.now)
        let store = DocumentStore(database)
        func czk(_ text: String) -> Money { Money(Fixtures.d(text), .czk) }
        let day = Fixtures.day("2026-11-10")
        try store.saveDraft(Fixtures.czkDraft(), now: Fixtures.now)
        try store.saveDraft(Fixtures.czkDraft(id: "doc-other", customer: Fixtures.czechCustomer(id: "cust-cz2")), now: Fixtures.now)
        try store.saveDraft(Fixtures.czkDraft(id: "doc-same"), now: Fixtures.now)
        try store.issue(id: "doc-cz", seriesID: "fv", now: Fixtures.now)
        try store.issue(id: "doc-other", seriesID: "fv", now: Fixtures.now)
        try store.issue(id: "doc-same", seriesID: "fv", now: Fixtures.now)
        try store.recordPayment(documentID: "doc-cz", on: day, amount: czk("12600"), now: Fixtures.now)

        #expect(throws: DataError.creditCustomerMismatch(sourceDocumentID: "doc-cz", targetDocumentID: "doc-other")) {
            try store.applyCredit(from: "doc-cz", to: "doc-other", amount: czk("500"), on: day, now: Fixtures.now)
        }
        #expect(try store.payments(for: "doc-other").isEmpty)
        #expect(try store.payments(for: "doc-cz").count == 1)

        let credit = try store.applyCredit(from: "doc-cz", to: "doc-same", amount: czk("500"), on: day, now: Fixtures.now)
        #expect(credit.documentID == "doc-same")
        #expect(try store.paymentState(for: "doc-cz").outstanding == czk("0"))
        #expect(try store.paymentState(for: "doc-same").outstanding == czk("11600"))
    }

    @Test func aReceiptIssuedBeforeItsPaymentStillNamesItsAdvance() throws {
        let database = try Fixtures.prepared()
        try Fixtures.addAdvanceSeries(database)
        let store = DocumentStore(database)
        let day = Fixtures.day("2026-11-10")
        let advance = try Fixtures.issuedAdvance(database)
        // The receipt is issued before any payment is recorded or attached.
        try store.saveDraft(Document.paymentTaxDocument(id: "dd1", forAdvanceRequest: advance, received: Fixtures.d("12100"), on: day), now: Fixtures.now)
        let receipt = try store.issue(id: "dd1", seriesID: "dd", now: Fixtures.now)
        try store.saveDraft(try Fixtures.finalInvoiceDraft(deducting: receipt), now: Fixtures.now)
        try store.issue(id: "final", seriesID: "fv", now: Fixtures.now)

        #expect(try store.deduction(ofReceipt: "dd1")?.advanceRequestID == advance.id)
        #expect(try store.deductions(ofAdvanceRequest: advance.id).map { $0.finalInvoiceID } == ["final"])
        let deducted = try store.state(for: advance.id, today: day)
        #expect(deducted.deductedInFinal)
        #expect(deducted.deductedBy == ["FV-2026-001"])
        #expect(throws: DataError.documentIsDeducted(advance.id)) {
            try store.closeAdvanceUnpaid(id: advance.id, reason: "x", now: Fixtures.now)
        }
        #expect(try store.closure(for: advance.id) == nil)

        // The payment recorded and attached afterwards agrees with the frozen link.
        let payment = try store.recordPayment(documentID: advance.id, on: day, amount: Money(Fixtures.d("12100"), .czk), now: Fixtures.now)
        #expect(try store.attachReceipt(paymentID: payment.id, documentID: "dd1", now: Fixtures.now).receiptDocumentID == "dd1")
        let paid = try store.state(for: advance.id, today: day)
        #expect(paid.deductedBy == ["FV-2026-001"])
        #expect(paid.taxDocumentIssued)
        #expect(try store.deduction(ofReceipt: "dd1")?.advanceRequestID == advance.id)
    }

    @Test func aDeductedReceiptWithoutItsAdvanceTakesNoPayment() throws {
        let database = try Fixtures.prepared()
        try Fixtures.addAdvanceSeries(database)
        let store = DocumentStore(database)
        let day = Fixtures.day("2026-11-10")
        let advance = try Fixtures.issuedAdvance(database)
        try store.saveDraft(Document.paymentTaxDocument(id: "dd1", forAdvanceRequest: advance, received: Fixtures.d("12100"), on: day), now: Fixtures.now)
        let receipt = try store.issue(id: "dd1", seriesID: "dd", now: Fixtures.now)
        try store.saveDraft(Fixtures.czkDraft(), now: Fixtures.now)
        try store.issue(id: "doc-cz", seriesID: "fv", now: Fixtures.now)
        // A frozen link that names no advance request (as written before the advance could be resolved).
        try database.queue.write { db in
            try db.execute(sql: """
                INSERT INTO advanceDeduction (id, finalInvoiceID, finalInvoiceNumber, receiptDocumentID, receiptNumber, advanceRequestID, createdAt)
                VALUES ('link-1', 'doc-cz', 'FV-2026-001', 'dd1', ?, NULL, '2026-11-05T05:00:00Z')
                """, arguments: [receipt.number ?? ""])
        }
        let payment = try store.recordPayment(documentID: advance.id, on: day, amount: Money(Fixtures.d("12100"), .czk), now: Fixtures.now)
        do {
            _ = try store.attachReceipt(paymentID: payment.id, documentID: "dd1", now: Fixtures.now)
            Issue.record("a payment was attached to a receipt deducted without its advance")
        } catch DataError.receiptMismatch(let paymentID, _) {
            #expect(paymentID == payment.id)
        }
        #expect(try store.payments(for: advance.id).first?.receiptDocumentID == nil)
    }

    @Test func aDeductedReceiptMustBeForTheSameCustomer() throws {
        let database = try Fixtures.prepared()
        try Fixtures.addAdvanceSeries(database)
        let store = DocumentStore(database)
        let day = Fixtures.day("2026-11-10")
        let advance = try Fixtures.issuedAdvance(database)
        // A receipt without a customer id (a one-off customer) for a final invoice of a stored customer.
        var oneOff = Document.paymentTaxDocument(id: "dd1", forAdvanceRequest: advance, received: Fixtures.d("12100"), on: day)
        oneOff.customerID = nil
        try store.saveDraft(oneOff, now: Fixtures.now)
        let receipt = try store.issue(id: "dd1", seriesID: "dd", now: Fixtures.now)
        try store.saveDraft(try Fixtures.finalInvoiceDraft(deducting: receipt), now: Fixtures.now)
        do {
            try store.issue(id: "final", seriesID: "fv", now: Fixtures.now)
            Issue.record("a final invoice deducted a receipt of another customer")
        } catch DataError.deductedDocumentInvalid(let number, _) {
            #expect(number == receipt.number)
        }
        #expect(try store.summary(id: "final")?.status == .draft)
        #expect(try NumberSeriesStore(database).peekNextNumber(seriesID: "fv", on: day) == "FV-2026-001")
        #expect(try store.deduction(ofReceipt: "dd1") == nil)
    }

    @Test func anIssuedPaymentTaxDocumentCarriesNoPaymentInstructions() throws {
        let database = try Fixtures.prepared()
        try Fixtures.addAdvanceSeries(database)
        let store = DocumentStore(database)
        let advance = try Fixtures.issuedAdvance(database)
        #expect(advance.payment != nil)
        let receipt = try Fixtures.issuedReceipt(database, advance: advance)
        #expect(receipt.payment == nil)
        #expect(try store.summary(id: "dd1")?.variableSymbol == nil)
        #expect(try store.document(id: "dd1")?.payment == nil)
        // A draft receipt that carries instructions loses them when issued.
        var withAccount = Document.paymentTaxDocument(id: "dd2", forAdvanceRequest: advance, received: Fixtures.d("100"), on: Fixtures.day("2026-11-11"))
        withAccount.payment = PaymentInstructions(bankConnection: Fixtures.bank, variableSymbol: PaymentSymbol.variable("777"))
        try store.saveDraft(withAccount, now: Fixtures.now)
        #expect(try store.issue(id: "dd2", seriesID: "dd", now: Fixtures.now).payment == nil)
    }

    @Test func paymentOfReceiptFindsTheNamingPayment() throws {
        let database = try Fixtures.prepared()
        try Fixtures.addAdvanceSeries(database)
        let store = DocumentStore(database)
        let advance = try Fixtures.issuedAdvance(database)
        let day = Fixtures.day("2026-11-10")
        let payment = try store.recordPayment(documentID: advance.id, on: day, amount: Money(Fixtures.d("12100"), .czk), now: Fixtures.now)
        try store.saveDraft(Document.paymentTaxDocument(id: "dd1", forAdvanceRequest: advance, received: Fixtures.d("12100"), on: day), now: Fixtures.now)
        #expect(try store.payment(ofReceipt: "dd1") == nil)
        _ = try store.attachReceipt(paymentID: payment.id, documentID: "dd1", now: Fixtures.now)
        let found = try store.payment(ofReceipt: "dd1")
        #expect(found?.id == payment.id)
        #expect(found?.receiptIssued == false)
        // Deleting the payment alone leaves an orphan draft receipt that no payment names.
        try store.deletePayment(id: payment.id, now: Fixtures.now)
        #expect(try store.payment(ofReceipt: "dd1") == nil)
        #expect(try store.document(id: "dd1")?.status == .draft)
        #expect(try store.payment(ofReceipt: "missing") == nil)
    }

    @Test func deletingAPaymentCanTakeItsDraftReceiptAlong() throws {
        let database = try Fixtures.prepared()
        try Fixtures.addAdvanceSeries(database)
        let store = DocumentStore(database)
        let advance = try Fixtures.issuedAdvance(database)
        let day = Fixtures.day("2026-11-10")
        let payment = try store.recordPayment(documentID: advance.id, on: day, amount: Money(Fixtures.d("12100"), .czk), now: Fixtures.now)
        try store.saveDraft(Document.paymentTaxDocument(id: "dd1", forAdvanceRequest: advance, received: Fixtures.d("12100"), on: day), now: Fixtures.now)
        _ = try store.attachReceipt(paymentID: payment.id, documentID: "dd1", now: Fixtures.now)

        try store.deletePayment(id: payment.id, deletingDraftReceipt: true, now: Fixtures.now)
        #expect(try store.document(id: "dd1") == nil)
        #expect(try store.payments(for: advance.id).isEmpty)
        let deletion = try AuditLog(database).events(entity: "document", id: "dd1").first { $0.action == "delete" }
        #expect(deletion?.details?["reason"] == "payment deleted")
        #expect(deletion?.details?["payment"] == payment.id)
        let deleted = try AuditLog(database).events(entity: "document", id: advance.id).last(where: { $0.action == "paymentDeleted" })
        #expect(deleted?.details?["receiptDeleted"] == "dd1")

        // An issued receipt still locks its payment, with or without the flag.
        let second = try Fixtures.issuedReceipt(database, advance: advance, id: "dd2", amount: Fixtures.d("100"), on: Fixtures.day("2026-11-11"))
        let locked = try store.payments(for: advance.id).first { $0.receiptDocumentID == second.id }
        #expect(throws: DataError.paymentLocked(locked?.id ?? "")) {
            try store.deletePayment(id: locked?.id ?? "", deletingDraftReceipt: true, now: Fixtures.now)
        }
        #expect(try store.document(id: "dd2")?.status == .issued)
    }

    @Test func aPaymentRecordedAgainUnderItsIDLinksItsKeptDraftReceipt() throws {
        let database = try Fixtures.prepared()
        try Fixtures.addAdvanceSeries(database)
        let store = DocumentStore(database)
        let advance = try Fixtures.issuedAdvance(database)
        let day = Fixtures.day("2026-11-10")
        let payment = try store.recordPayment(documentID: advance.id, on: day, amount: Money(Fixtures.d("12100"), .czk), now: Fixtures.now)
        try store.saveDraft(Document.paymentTaxDocument(id: "dd1", forAdvanceRequest: advance, received: Fixtures.d("12100"), on: day), now: Fixtures.now)
        _ = try store.attachReceipt(paymentID: payment.id, documentID: "dd1", now: Fixtures.now)

        // "Delete Payment Only": the draft stays behind, and the event names it.
        try store.deletePayment(id: payment.id, now: Fixtures.now)
        #expect(try store.document(id: "dd1")?.status == .draft)
        #expect(try store.payments(for: advance.id).isEmpty)
        let deleted = try AuditLog(database).events(entity: "document", id: advance.id).last(where: { $0.action == "paymentDeleted" })
        #expect(deleted?.details?["receiptKept"] == "dd1")
        #expect(deleted?.details?["receiptDeleted"] == nil)

        // Undo records the payment again under its id and links the draft back.
        let restored = try store.recordPayment(documentID: advance.id, id: payment.id, on: day, amount: payment.amount, now: Fixtures.now)
        #expect(restored.id == payment.id)
        _ = try store.attachReceipt(paymentID: payment.id, documentID: "dd1", now: Fixtures.now)
        #expect(try store.payment(ofReceipt: "dd1")?.id == payment.id)
        #expect(try store.payments(for: advance.id).first?.receiptDocumentID == "dd1")

        // One id, one row: a second payment under it is refused by the database.
        #expect(throws: DatabaseError.self) {
            try store.recordPayment(documentID: advance.id, id: payment.id, on: day, amount: payment.amount, now: Fixtures.now)
        }
        #expect(try store.payments(for: advance.id).count == 1)
    }

    @Test func anAdvancePaidInTwoPartsNamesItsFinalInvoiceOnce() throws {
        let database = try Fixtures.prepared()
        try Fixtures.addAdvanceSeries(database)
        let store = DocumentStore(database)
        let advance = try Fixtures.issuedAdvance(database)
        let first = try Fixtures.issuedReceipt(database, advance: advance, id: "dd1", amount: Fixtures.d("6050"), on: Fixtures.day("2026-11-10"))
        let second = try Fixtures.issuedReceipt(database, advance: advance, id: "dd2", amount: Fixtures.d("6050"), on: Fixtures.day("2026-11-12"))

        var draft = try Fixtures.finalInvoiceDraft(deducting: first)
        draft.advanceDeductions += second.advanceDeductions(totals: try DocumentTotals.compute(for: second))
        try store.saveDraft(draft, now: Fixtures.now)
        try store.issue(id: "final", seriesID: "fv", now: Fixtures.now)
        #expect(try store.deductions(ofFinalInvoice: "final").count == 2)
        #expect(try store.deductions(ofAdvanceRequest: advance.id).count == 2)

        let state = try store.state(for: advance.id, today: Fixtures.day("2026-12-01"))
        #expect(state.deductedInFinal)
        #expect(state.deductedBy == ["FV-2026-001"])
    }
}
