import Foundation
import GRDB
import Testing
import InvoicingCore
@testable import InvoicingData

/// Advances paid on § 64 goods: no payment tax document, settled on the final invoice as paid in advance
/// (ADR 0012).
@Suite struct PaidAdvanceStoreTests {
    static let goodsLine = DocumentLine(id: "l1", text: "Spindle bearing SKF 7014", quantity: 10, unit: "pcs", unitPrice: 100,
                                        treatment: .intraCommunityGoods)

    /// A database with the advance series and an issued EUR advance request for 1 000 EUR of § 64 goods to the
    /// German customer (ZF-2026-001).
    static func preparedWithGoodsAdvance(lines: [DocumentLine] = [goodsLine]) throws -> (AppDatabase, Document) {
        let database = try Fixtures.prepared()
        try Fixtures.addAdvanceSeries(database)
        var request = Fixtures.eurDraft(id: "adv")
        request.kind = .advanceRequest
        request.taxPointDate = nil
        request.exchangeRate = nil
        request.lines = lines
        let store = DocumentStore(database)
        try store.saveDraft(request, now: Fixtures.now)
        return (database, try store.issue(id: "adv", seriesID: "zf", now: Fixtures.now))
    }

    /// A final invoice draft for the same 1 000 EUR of goods listing `paid` as paid in advance.
    static func finalInvoiceDraft(id: String = "final", paid: [PaidAdvance]) -> Document {
        var document = Fixtures.eurDraft(id: id)
        document.kind = .finalInvoice
        document.lines = [goodsLine]
        document.paidAdvances = paid.isEmpty ? nil : paid
        return document
    }

    static func eur(_ text: String) -> Money { Money(Fixtures.d(text), .eur) }

    /// The payment tax document `id` for `amount` EUR received on `iso` on the advance, with the rate of a day
    /// before (a tax document in EUR needs one): the flow of ADR 0007, which goods advances took before v3.
    static func receiptDraft(id: String, for advance: Document, amount: String, on iso: String) -> Document {
        var draft = Document.paymentTaxDocument(id: id, forAdvanceRequest: advance, received: Fixtures.d(amount), on: Fixtures.day(iso))
        draft.exchangeRate = ExchangeRate(currency: .eur, amount: 1, czkPerAmount: Fixtures.d("24.300"), validFor: Fixtures.day("2026-10-30"),
                                          source: .cnb(order: 210))
        return draft
    }

    /// Records a payment of `amount` EUR on the advance and links its payment tax document `id` (`receiptDraft`), issued
    /// from the "dd" series unless `issuing` is false; returns the payment.
    static func paymentWithReceipt(_ database: AppDatabase, advance: Document, id: String, amount: String, on iso: String = "2026-11-02",
                                   issuing: Bool = true) throws -> DocumentPayment {
        let store = DocumentStore(database)
        let payment = try store.recordPayment(documentID: advance.id, on: Fixtures.day(iso), amount: Self.eur(amount), now: Fixtures.now)
        try store.saveDraft(Self.receiptDraft(id: id, for: advance, amount: amount, on: iso), now: Fixtures.now)
        _ = try store.attachReceipt(paymentID: payment.id, documentID: id, now: Fixtures.now)
        if issuing {
            _ = try store.issue(id: id, seriesID: "dd", now: Fixtures.now)
        }
        return payment
    }

    @Test func aGoodsAdvanceNeedsNoTaxDocumentAndReadsPaid() throws {
        let (database, advance) = try Self.preparedWithGoodsAdvance()
        let store = DocumentStore(database)
        _ = try store.recordPayment(documentID: advance.id, on: Fixtures.day("2026-11-02"), amount: Self.eur("1000"), now: Fixtures.now)
        let state = try store.state(for: advance.id, today: Fixtures.day("2026-11-05"))
        #expect(!state.taxDocumentRequired)
        #expect(!state.taxDocumentIssued)
        #expect(state.settlement == .paid)
        #expect(!state.deductedInFinal)
        // The row records the treatments, so the lists need not decode the snapshot.
        let treatments = try database.queue.read { db in try String.fetchOne(db, sql: "SELECT treatments FROM document WHERE id = 'adv'") }
        #expect(treatments == "[\"intraCommunityGoods\"]")
    }

    @Test func theFinalInvoiceSettlesThePaymentAndLocksIt() throws {
        let (database, advance) = try Self.preparedWithGoodsAdvance()
        let store = DocumentStore(database)
        let payment = try store.recordPayment(documentID: advance.id, on: Fixtures.day("2026-11-02"), amount: Self.eur("400"), now: Fixtures.now)
        let candidates = try store.paidAdvanceCandidates(ofAdvanceRequest: advance.id)
        #expect(candidates.map(\.payment.id) == [payment.id])
        #expect(candidates.first?.available == Self.eur("400"))
        #expect(try store.paidAdvanceCandidates(customerID: "cust-de", currency: .eur).map(\.id) == [payment.id])
        #expect(try store.paidAdvanceCandidates(customerID: "cust-de", currency: .czk).isEmpty)

        try store.saveDraft(Self.finalInvoiceDraft(paid: candidates.map(\.paidAdvance)), now: Fixtures.now)
        let final = try store.issue(id: "final", seriesID: "fv", now: Fixtures.now)
        let summary = try #require(try store.summary(id: "final"))
        // The value of the supply stays whole; only the amount due drops.
        #expect(summary.totalGross == Self.eur("1000"))
        #expect(summary.paidInAdvance == Self.eur("400"))
        #expect(summary.amountDue == Self.eur("600"))
        #expect(try store.paymentState(for: "final").outstanding == Self.eur("600"))

        let links = try store.paidAdvances(ofFinalInvoice: "final")
        #expect(links.count == 1)
        #expect(links.first?.paymentID == payment.id)
        #expect(links.first?.advanceNumber == advance.number)
        #expect(links.first?.amount == Self.eur("400"))
        #expect(try store.paidAdvance(ofPayment: payment.id)?.finalInvoiceNumber == final.number)
        #expect(try store.paidAdvances(ofAdvanceRequest: advance.id).map(\.finalInvoiceID) == ["final"])

        let state = try store.state(for: advance.id, today: Fixtures.day("2026-11-05"))
        #expect(state.deductedInFinal)
        #expect(state.deductedBy == [final.number ?? ""])
        #expect(try store.paidAdvanceCandidates(ofAdvanceRequest: advance.id).isEmpty)

        // The settled payment stays as it is: no deletion, no tax document, no change of its money.
        let settled = DataError.paymentSettled(paymentID: payment.id, finalInvoiceNumber: final.number ?? "")
        #expect(throws: settled) { try store.deletePayment(id: payment.id, now: Fixtures.now) }
        try store.saveDraft(Document.paymentTaxDocument(id: "dd1", forAdvanceRequest: advance, received: Fixtures.d("400"),
                                                        on: Fixtures.day("2026-11-02")), now: Fixtures.now)
        #expect(throws: settled) { try store.attachReceipt(paymentID: payment.id, documentID: "dd1", now: Fixtures.now) }
        #expect(throws: DatabaseError.self) {
            try database.queue.write { db in try db.execute(sql: "DELETE FROM documentPayment WHERE id = ?", arguments: [payment.id]) }
        }
        #expect(throws: DatabaseError.self) {
            try database.queue.write { db in try db.execute(sql: "UPDATE documentPayment SET amount = 1 WHERE id = ?", arguments: [payment.id]) }
        }
        #expect(throws: DatabaseError.self) {
            try database.queue.write { db in try db.execute(sql: "DELETE FROM paidAdvance") }
        }
        // Its note may still change.
        try database.queue.write { db in try db.execute(sql: "UPDATE documentPayment SET note = 'x' WHERE id = ?", arguments: [payment.id]) }
    }

    @Test func aPaymentIsSettledByOneFinalInvoiceOnly() throws {
        let (database, advance) = try Self.preparedWithGoodsAdvance()
        let store = DocumentStore(database)
        _ = try store.recordPayment(documentID: advance.id, on: Fixtures.day("2026-11-02"), amount: Self.eur("400"), now: Fixtures.now)
        let paid = try store.paidAdvanceCandidates(ofAdvanceRequest: advance.id).map(\.paidAdvance)
        try store.saveDraft(Self.finalInvoiceDraft(id: "final-1", paid: paid), now: Fixtures.now)
        try store.saveDraft(Self.finalInvoiceDraft(id: "final-2", paid: paid), now: Fixtures.now)
        let first = try store.issue(id: "final-1", seriesID: "fv", now: Fixtures.now)
        #expect(throws: DataError.advanceAlreadySettled(advanceNumber: advance.number ?? "", by: first.number ?? "")) {
            try store.issue(id: "final-2", seriesID: "fv", now: Fixtures.now)
        }
        // The failed issue left the draft and the series untouched.
        #expect(try store.summary(id: "final-2")?.status == .draft)
    }

    @Test func refundsLeaveWhatWasSettled() throws {
        let (database, advance) = try Self.preparedWithGoodsAdvance()
        let store = DocumentStore(database)
        _ = try store.recordPayment(documentID: advance.id, on: Fixtures.day("2026-11-02"), amount: Self.eur("1000"), now: Fixtures.now)
        _ = try store.recordRefund(documentID: advance.id, on: Fixtures.day("2026-11-03"), amount: Self.eur("200"), now: Fixtures.now)
        // What is offered is what the advance still holds.
        let candidates = try store.paidAdvanceCandidates(ofAdvanceRequest: advance.id)
        #expect(candidates.map(\.available) == [Self.eur("800")])
        try store.saveDraft(Self.finalInvoiceDraft(paid: candidates.map(\.paidAdvance)), now: Fixtures.now)
        _ = try store.issue(id: "final", seriesID: "fv", now: Fixtures.now)
        #expect(throws: DataError.refundExceedsAvailable(documentID: advance.id, available: Self.eur("0"), requested: Self.eur("1"))) {
            try store.recordRefund(documentID: advance.id, on: Fixtures.day("2026-11-06"), amount: Self.eur("1"), now: Fixtures.now)
        }
    }

    @Test func listingMoreThanTheAdvanceHoldsIsRefused() throws {
        let (database, advance) = try Self.preparedWithGoodsAdvance()
        let store = DocumentStore(database)
        let payment = try store.recordPayment(documentID: advance.id, on: Fixtures.day("2026-11-02"), amount: Self.eur("1000"), now: Fixtures.now)
        _ = try store.recordRefund(documentID: advance.id, on: Fixtures.day("2026-11-03"), amount: Self.eur("300"), now: Fixtures.now)
        let whole = PaidAdvance(advanceNumber: advance.number ?? "", paidOn: Fixtures.day("2026-11-02"), amount: 1000, currency: .eur,
                                paymentID: payment.id, advanceTreatment: .intraCommunityGoods)
        try store.saveDraft(Self.finalInvoiceDraft(paid: [whole]), now: Fixtures.now)
        #expect(throws: DataError.paidAdvancesExceedPaid(advanceNumber: advance.number ?? "", available: Self.eur("700"), listed: Self.eur("1000"))) {
            try store.issue(id: "final", seriesID: "fv", now: Fixtures.now)
        }
    }

    @Test func eachRowMustMatchItsPayment() throws {
        let (database, advance) = try Self.preparedWithGoodsAdvance()
        let store = DocumentStore(database)
        let payment = try store.recordPayment(documentID: advance.id, on: Fixtures.day("2026-11-02"), amount: Self.eur("400"), now: Fixtures.now)
        let number = advance.number ?? ""
        func row(_ amount: String, on iso: String = "2026-11-02", paymentID: String? = nil, advanceNumber: String? = nil) -> PaidAdvance {
            PaidAdvance(advanceNumber: advanceNumber ?? number, paidOn: Fixtures.day(iso), amount: Fixtures.d(amount), currency: .eur,
                        paymentID: paymentID, advanceTreatment: .intraCommunityGoods)
        }
        let refused: [(String, PaidAdvance)] = [
            ("another day", row("400", on: "2026-11-03", paymentID: payment.id)),
            ("more than received", row("401", paymentID: payment.id)),
            ("another advance number", row("400", paymentID: payment.id, advanceNumber: "ZF-2026-999")),
            ("a stored advance without its payment", row("400")),
        ]
        for (label, paid) in refused {
            try store.saveDraft(Self.finalInvoiceDraft(id: "final", paid: [paid]), now: Fixtures.now)
            var failed = false
            do {
                _ = try store.issue(id: "final", seriesID: "fv", now: Fixtures.now)
            } catch let error as DataError {
                if case .paidAdvanceInvalid(let refusedNumber, _) = error { failed = refusedNumber == paid.advanceNumber }
            }
            #expect(failed, "\(label) was not refused as paidAdvanceInvalid")
        }
        // An advance from before the app is allowed and named in the audit event.
        try store.saveDraft(Self.finalInvoiceDraft(id: "final", paid: [row("250", advanceNumber: "ZF-2025-077")]), now: Fixtures.now)
        _ = try store.issue(id: "final", seriesID: "fv", now: Fixtures.now)
        #expect(try store.paidAdvances(ofFinalInvoice: "final").isEmpty)
        let events = try AuditLog(database).events(entity: "document", id: "final")
        #expect(events.last?.details?["externalPaidAdvances"] == "ZF-2025-077")
    }

    @Test func aPaymentWithAnIssuedTaxDocumentIsDeductedNotListed() throws {
        let (database, advance) = try Self.preparedWithGoodsAdvance()
        let store = DocumentStore(database)
        let payment = try store.recordPayment(documentID: advance.id, on: Fixtures.day("2026-11-02"), amount: Self.eur("400"), now: Fixtures.now)
        var receipt = Document.paymentTaxDocument(id: "dd1", forAdvanceRequest: advance, received: Fixtures.d("400"), on: Fixtures.day("2026-11-02"))
        // A tax document in EUR needs the rate of a day on or before the payment.
        receipt.exchangeRate = ExchangeRate(currency: .eur, amount: 1, czkPerAmount: Fixtures.d("24.300"), validFor: Fixtures.day("2026-10-30"),
                                            source: .cnb(order: 210))
        try store.saveDraft(receipt, now: Fixtures.now)
        _ = try store.attachReceipt(paymentID: payment.id, documentID: "dd1", now: Fixtures.now)
        _ = try store.issue(id: "dd1", seriesID: "dd", now: Fixtures.now)
        #expect(try store.paidAdvanceCandidates(ofAdvanceRequest: advance.id).isEmpty)
        let listed = PaidAdvance(advanceNumber: advance.number ?? "", paidOn: Fixtures.day("2026-11-02"), amount: 400, currency: .eur,
                                 paymentID: payment.id, advanceTreatment: .intraCommunityGoods)
        try store.saveDraft(Self.finalInvoiceDraft(paid: [listed]), now: Fixtures.now)
        var refused = false
        do {
            _ = try store.issue(id: "final", seriesID: "fv", now: Fixtures.now)
        } catch DataError.paidAdvanceInvalid {
            refused = true
        }
        #expect(refused)
    }

    @Test func anAdvanceWithOtherLinesKeepsTheTaxDocumentFlow() throws {
        let service = DocumentLine(id: "l2", text: "Transport", quantity: 1, unitPrice: 50, treatment: .reverseChargeEU)
        let (database, advance) = try Self.preparedWithGoodsAdvance(lines: [Self.goodsLine, service])
        let store = DocumentStore(database)
        _ = try store.recordPayment(documentID: advance.id, on: Fixtures.day("2026-11-02"), amount: Self.eur("1050"), now: Fixtures.now)
        #expect(try store.state(for: advance.id, today: Fixtures.day("2026-11-05")).taxDocumentRequired)
        #expect(try store.paidAdvanceCandidates(ofAdvanceRequest: advance.id).isEmpty)
    }

    @Test func rowsWithoutTheTreatmentsColumnReadTheSnapshot() throws {
        var advance = Fixtures.eurDraft(id: "adv")
        advance.kind = .advanceRequest
        advance.lines = [Self.goodsLine]
        var record = try DocumentRecord(document: advance, totals: nil, createdAt: "2026-11-05T05:00:00Z", updatedAt: "2026-11-05T05:00:00Z",
                                        issuedAt: nil)
        #expect(try record.isIntraCommunityGoodsOnly())
        record.treatments = nil
        #expect(try record.isIntraCommunityGoodsOnly())
        advance.lines.append(DocumentLine(id: "l2", text: "Transport", quantity: 1, unitPrice: 50, treatment: .reverseChargeEU))
        record = try DocumentRecord(document: advance, totals: nil, createdAt: "2026-11-05T05:00:00Z", updatedAt: "2026-11-05T05:00:00Z",
                                    issuedAt: nil)
        record.treatments = nil
        #expect(try !record.isIntraCommunityGoodsOnly())
    }

    @Test func moneyAnIssuedTaxDocumentCoversIsNotListedAgain() throws {
        // Before v3 a goods advance took payment tax documents: 400 has one (a final invoice deducts it under
        // § 37a), 600 has none and was refunded. The advance holds 400, all of it the document's, so nothing is
        // left to list as paid in advance.
        let (database, advance) = try Self.preparedWithGoodsAdvance()
        let store = DocumentStore(database)
        _ = try Self.paymentWithReceipt(database, advance: advance, id: "dd1", amount: "400")
        let other = try store.recordPayment(documentID: advance.id, on: Fixtures.day("2026-11-03"), amount: Self.eur("600"), now: Fixtures.now)
        _ = try store.recordRefund(documentID: advance.id, on: Fixtures.day("2026-11-04"), amount: Self.eur("600"), now: Fixtures.now)
        #expect(try store.paidAdvanceCandidates(ofAdvanceRequest: advance.id).isEmpty)
        let listed = PaidAdvance(advanceNumber: advance.number ?? "", paidOn: Fixtures.day("2026-11-03"), amount: 400, currency: .eur,
                                 paymentID: other.id, advanceTreatment: .intraCommunityGoods)
        try store.saveDraft(Self.finalInvoiceDraft(paid: [listed]), now: Fixtures.now)
        #expect(throws: DataError.paidAdvancesExceedPaid(advanceNumber: advance.number ?? "", available: Self.eur("0"), listed: Self.eur("400"))) {
            try store.issue(id: "final", seriesID: "fv", now: Fixtures.now)
        }
    }

    @Test func aPaymentIsOfferedWhatTheTaxDocumentsLeave() throws {
        // 400 with an issued payment tax document, 900 without, 300 refunded: the advance holds 1 000, of which the
        // document covers 400, so the 900 is offered for 600 and listing all of it is refused.
        let (database, advance) = try Self.preparedWithGoodsAdvance()
        let store = DocumentStore(database)
        _ = try Self.paymentWithReceipt(database, advance: advance, id: "dd1", amount: "400")
        let other = try store.recordPayment(documentID: advance.id, on: Fixtures.day("2026-11-03"), amount: Self.eur("900"), now: Fixtures.now)
        _ = try store.recordRefund(documentID: advance.id, on: Fixtures.day("2026-11-04"), amount: Self.eur("300"), now: Fixtures.now)
        let candidates = try store.paidAdvanceCandidates(ofAdvanceRequest: advance.id)
        #expect(candidates.map(\.payment.id) == [other.id])
        #expect(candidates.map(\.available) == [Self.eur("600")])
        let whole = PaidAdvance(advanceNumber: advance.number ?? "", paidOn: Fixtures.day("2026-11-03"), amount: 900, currency: .eur,
                                paymentID: other.id, advanceTreatment: .intraCommunityGoods)
        try store.saveDraft(Self.finalInvoiceDraft(paid: [whole]), now: Fixtures.now)
        #expect(throws: DataError.paidAdvancesExceedPaid(advanceNumber: advance.number ?? "", available: Self.eur("600"), listed: Self.eur("900"))) {
            try store.issue(id: "final", seriesID: "fv", now: Fixtures.now)
        }
        // What is offered is accepted; a refund may then take nothing, the rest being the tax document's.
        try store.saveDraft(Self.finalInvoiceDraft(paid: candidates.map(\.paidAdvance)), now: Fixtures.now)
        _ = try store.issue(id: "final", seriesID: "fv", now: Fixtures.now)
        #expect(throws: DataError.refundExceedsAvailable(documentID: advance.id, available: Self.eur("0"), requested: Self.eur("1"))) {
            try store.recordRefund(documentID: advance.id, on: Fixtures.day("2026-11-05"), amount: Self.eur("1"), now: Fixtures.now)
        }
    }

    @Test func aRefundAPaymentWasSettledNetOfStays() throws {
        // 1 000 received, 300 refunded, the final invoice settles the 700 left: without the refund the advance would
        // hold 300 that no final invoice can list, as the payment is settled.
        let (database, advance) = try Self.preparedWithGoodsAdvance()
        let store = DocumentStore(database)
        _ = try store.recordPayment(documentID: advance.id, on: Fixtures.day("2026-11-02"), amount: Self.eur("1000"), now: Fixtures.now)
        let refund = try store.recordRefund(documentID: advance.id, on: Fixtures.day("2026-11-03"), amount: Self.eur("300"), now: Fixtures.now)
        let paid = try store.paidAdvanceCandidates(ofAdvanceRequest: advance.id).map(\.paidAdvance)
        #expect(paid.map(\.amount) == [Fixtures.d("700")])
        try store.saveDraft(Self.finalInvoiceDraft(paid: paid), now: Fixtures.now)
        let final = try store.issue(id: "final", seriesID: "fv", now: Fixtures.now)
        #expect(throws: DataError.paymentBacksSettlement(paymentID: refund.id, finalInvoiceNumber: final.number ?? "")) {
            try store.deletePayment(id: refund.id, now: Fixtures.now)
        }
        #expect(try store.payments(for: advance.id).contains(where: { $0.id == refund.id }))
    }

    @Test func aPaymentARefundRestsOnStays() throws {
        let (database, advance) = try Self.preparedWithGoodsAdvance()
        let store = DocumentStore(database)
        let first = try store.recordPayment(documentID: advance.id, on: Fixtures.day("2026-11-02"), amount: Self.eur("400"), now: Fixtures.now)
        let second = try store.recordPayment(documentID: advance.id, on: Fixtures.day("2026-11-03"), amount: Self.eur("600"), now: Fixtures.now)
        let paid = try store.paidAdvanceCandidates(ofAdvanceRequest: advance.id).filter { $0.payment.id == first.id }.map(\.paidAdvance)
        try store.saveDraft(Self.finalInvoiceDraft(paid: paid), now: Fixtures.now)
        let final = try store.issue(id: "final", seriesID: "fv", now: Fixtures.now)
        // A refund of money no final invoice settled can still be corrected.
        let mistake = try store.recordRefund(documentID: advance.id, on: Fixtures.day("2026-11-04"), amount: Self.eur("200"), now: Fixtures.now)
        try store.deletePayment(id: mistake.id, now: Fixtures.now)
        // Once a refund took the second payment's money, that payment cannot go: the advance would hold less than
        // the final invoice settled.
        _ = try store.recordRefund(documentID: advance.id, on: Fixtures.day("2026-11-04"), amount: Self.eur("600"), now: Fixtures.now)
        #expect(throws: DataError.paymentBacksSettlement(paymentID: second.id, finalInvoiceNumber: final.number ?? "")) {
            try store.deletePayment(id: second.id, now: Fixtures.now)
        }
        #expect(try store.payments(for: advance.id).contains(where: { $0.id == second.id }))
    }

    @Test func aGoodsAdvanceWithATaxDocumentFromBeforeKeepsThatFlow() throws {
        // Before v3 a goods advance took payment tax documents (ADR 0007). One already linked to a payment, a draft
        // or an issued one, keeps the advance in that flow, so its badges and Open Tax Document read as before.
        let (database, advance) = try Self.preparedWithGoodsAdvance()
        let store = DocumentStore(database)
        let today = Fixtures.day("2026-11-05")
        _ = try Self.paymentWithReceipt(database, advance: advance, id: "dd1", amount: "400", issuing: false)
        #expect(try store.state(for: advance.id, today: today).taxDocumentRequired)
        // Without the draft it is a goods advance like any other.
        try store.deleteDraft(id: "dd1", now: Fixtures.now)
        #expect(try !store.state(for: advance.id, today: today).taxDocumentRequired)
        _ = try Self.paymentWithReceipt(database, advance: advance, id: "dd2", amount: "600")
        let state = try store.state(for: advance.id, today: today)
        #expect(state.taxDocumentRequired)
        // The first payment has no tax document any more.
        #expect(!state.taxDocumentIssued)
    }

    @Test func replaceCannotRewriteASettledLink() throws {
        let (database, advance) = try Self.preparedWithGoodsAdvance()
        let store = DocumentStore(database)
        let payment = try store.recordPayment(documentID: advance.id, on: Fixtures.day("2026-11-02"), amount: Self.eur("400"), now: Fixtures.now)
        let paid = try store.paidAdvanceCandidates(ofAdvanceRequest: advance.id).map(\.paidAdvance)
        try store.saveDraft(Self.finalInvoiceDraft(paid: paid), now: Fixtures.now)
        let final = try store.issue(id: "final", seriesID: "fv", now: Fixtures.now)
        let link = try #require(try store.paidAdvances(ofFinalInvoice: "final").first)
        let columns = "(id, finalInvoiceID, finalInvoiceNumber, paymentID, advanceRequestID, advanceNumber, amount, currency, createdAt)"
        // The same id for another amount, or a new id taking the settled payment: REPLACE would remove the frozen
        // row without firing its delete trigger.
        #expect(throws: DatabaseError.self) {
            try database.queue.write { db in
                try db.execute(sql: "INSERT OR REPLACE INTO paidAdvance \(columns) VALUES (?, 'final', ?, ?, 'adv', ?, 1, 'EUR', 't')",
                               arguments: [link.id, link.finalInvoiceNumber, payment.id, link.advanceNumber])
            }
        }
        #expect(throws: DatabaseError.self) {
            try database.queue.write { db in
                try db.execute(sql: "REPLACE INTO paidAdvance \(columns) VALUES ('evil', 'final', ?, ?, 'adv', ?, 1, 'EUR', 't')",
                               arguments: [link.finalInvoiceNumber, payment.id, link.advanceNumber])
            }
        }
        let kept = try store.paidAdvances(ofFinalInvoice: "final")
        #expect(kept.map(\.id) == [link.id])
        #expect(kept.first?.amount == Self.eur("400"))
        // The payment is still settled, so still locked.
        #expect(throws: DataError.paymentSettled(paymentID: payment.id, finalInvoiceNumber: final.number ?? "")) {
            try store.deletePayment(id: payment.id, now: Fixtures.now)
        }
    }

    @Test func aSettledCreditCannotBeDeletedFromItsOtherSide() throws {
        // 400 overpaid on an invoice moves to the goods advance, and the final invoice settles it as paid in advance:
        // deleting the credit from the invoice's side names that final invoice, not a tax document.
        let (database, advance) = try Self.preparedWithGoodsAdvance()
        let store = DocumentStore(database)
        try store.saveDraft(Fixtures.eurDraft(), now: Fixtures.now)
        _ = try store.issue(id: "doc-eu", seriesID: "fv", now: Fixtures.now)
        _ = try store.recordPayment(documentID: "doc-eu", on: Fixtures.day("2026-11-02"), amount: Self.eur("1400"), now: Fixtures.now)
        let credit = try store.applyCredit(from: "doc-eu", to: advance.id, amount: Self.eur("400"), on: Fixtures.day("2026-11-03"), now: Fixtures.now)
        let paid = try store.paidAdvanceCandidates(ofAdvanceRequest: advance.id).map(\.paidAdvance)
        #expect(paid.map(\.paymentID) == [credit.id])
        try store.saveDraft(Self.finalInvoiceDraft(paid: paid), now: Fixtures.now)
        let final = try store.issue(id: "final", seriesID: "fv", now: Fixtures.now)
        let creditOut = try #require(credit.relatedPaymentID)
        #expect(throws: DataError.relatedPaymentSettled(paymentID: creditOut, relatedPaymentID: credit.id, finalInvoiceNumber: final.number ?? "")) {
            try store.deletePayment(id: creditOut, now: Fixtures.now)
        }
        #expect(try store.payments(for: "doc-eu").count == 2)
    }
}
