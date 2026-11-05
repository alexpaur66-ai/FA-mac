import Foundation
import GRDB
import InvoicingCore

// The state of stored documents for lists and badges (ADR 0007).
extension DocumentStore {
    /// The state of one document as of `today`.
    public func state(for id: String, today: CalendarDay) throws -> DocumentState {
        try database.queue.read { db in
            guard let record = try DocumentRecord.fetchOne(db, key: id) else { throw DataError.documentNotFound(id) }
            guard let state = try Self.states(db, records: [record], today: today).first else { throw DataError.documentNotFound(id) }
            return state
        }
    }

    /// The states of the documents matching the filter, in the order of `summaries(_:)`.
    public func states(_ filter: DocumentFilter = DocumentFilter(), today: CalendarDay) throws -> [DocumentState] {
        try database.queue.read { db in try Self.states(db, filter: filter, today: today) }
    }

    /// A GRDB observation of `states(_:today:)` for the UI: it delivers the current value and then a new
    /// value whenever documents, payments, closures or deductions change
    /// (`observation.start(in: database.queue, ...)` or `observation.values(in: database.queue)`).
    public func observeStates(_ filter: DocumentFilter = DocumentFilter(), today: CalendarDay) -> ValueObservation<ValueReducers.Fetch<[DocumentState]>> {
        ValueObservation.tracking { db in try Self.states(db, filter: filter, today: today) }
    }

    static func states(_ db: Database, filter: DocumentFilter, today: CalendarDay) throws -> [DocumentState] {
        try states(db, records: try request(filter).fetchAll(db), today: today)
    }

    /// Payment totals of one document: net paid, incoming payments, incoming payments without an issued receipt,
    /// payments linked to a payment tax document (a draft or an issued one).
    struct PaymentSums: Decodable, FetchableRecord {
        var documentID: String
        var paid: Int64
        var incoming: Int
        var missingReceipts: Int
        var withReceipt: Int
    }

    static func states(_ db: Database, records: [DocumentRecord], today: CalendarDay) throws -> [DocumentState] {
        guard !records.isEmpty else { return [] }
        var sums: [String: PaymentSums] = [:]
        for row in try PaymentSums.fetchAll(db, sql: """
            SELECT p.documentID AS documentID,
                   COALESCE(SUM(p.amount), 0) AS paid,
                   COALESCE(SUM(CASE WHEN p.kind IN ('received', 'creditIn') THEN 1 ELSE 0 END), 0) AS incoming,
                   COALESCE(SUM(CASE WHEN p.kind IN ('received', 'creditIn')
                                      AND NOT EXISTS (SELECT 1 FROM document r WHERE r.id = p.receiptDocumentID AND r.status = 'issued')
                                     THEN 1 ELSE 0 END), 0) AS missingReceipts,
                   COALESCE(SUM(CASE WHEN p.receiptDocumentID IS NOT NULL THEN 1 ELSE 0 END), 0) AS withReceipt
            FROM documentPayment p
            GROUP BY p.documentID
            """) {
            sums[row.documentID] = row
        }
        var closures: [String: DocumentClosureRecord] = [:]
        for closure in try DocumentClosureRecord.fetchAll(db) { closures[closure.documentID] = closure }
        var deductedBy: [String: [String]] = [:]
        for link in try AdvanceDeductionRecord.filter(Column("advanceRequestID") != nil).order(Column("finalInvoiceNumber")).fetchAll(db) {
            // A final invoice that deducts two receipts of one advance is named once.
            if let advanceID = link.advanceRequestID, deductedBy[advanceID]?.contains(link.finalInvoiceNumber) != true {
                deductedBy[advanceID, default: []].append(link.finalInvoiceNumber)
            }
        }
        // A final invoice that settled payments of a § 64 goods advance as paid in advance (ADR 0012) settles it too.
        for link in try PaidAdvanceRecord.order(Column("finalInvoiceNumber")).fetchAll(db)
        where deductedBy[link.advanceRequestID]?.contains(link.finalInvoiceNumber) != true {
            deductedBy[link.advanceRequestID, default: []].append(link.finalInvoiceNumber)
        }

        var states: [DocumentState] = []
        states.reserveCapacity(records.count)
        for record in records {
            let summary = try record.summary()
            let currency = summary.currency
            let sum = sums[record.id]
            let dueUnits = summary.status == .draft ? 0 : (record.amountDue ?? 0)
            // A payment tax document records a payment booked on its advance request: it reads as paid in
            // full, with nothing outstanding.
            let isReceipt = summary.kind == .paymentTaxDocument && summary.status != .draft
            let paidUnits = summary.status == .draft ? 0 : (isReceipt ? dueUnits : (sum?.paid ?? 0))
            let outstandingUnits = dueUnits - paidUnits
            let closure = try closures[record.id]?.closure()

            let settlement: DocumentSettlement
            if summary.status == .draft {
                settlement = .draft
            } else if closure?.kind == .closedUnpaid {
                settlement = .closedUnpaid
            } else if summary.kind == .paymentTaxDocument {
                // A payment tax document records money already received.
                settlement = .paid
            } else if paidUnits == 0 && dueUnits == 0 {
                settlement = summary.kind == .finalInvoice ? .settledByAdvances : .paid
            } else if paidUnits <= 0 && outstandingUnits > 0 {
                settlement = .open
            } else if outstandingUnits > 0 {
                settlement = .partlyPaid
            } else if outstandingUnits == 0 {
                settlement = .paid
            } else {
                settlement = .overpaid
            }

            let overdue = summary.status == .issued && closure == nil && summary.kind != .paymentTaxDocument
                && (settlement == .open || settlement == .partlyPaid) && summary.dueDate < today
            let incoming = sum?.incoming ?? 0
            let deductions = deductedBy[record.id] ?? []
            // Money received on an advance for § 64 goods needs no payment tax document (ADR 0012). An advance
            // whose payments already have one (a draft or an issued one, made before v3) keeps that flow, so its
            // badge and its tax documents read as before.
            var taxDocumentRequired = true
            if summary.kind == .advanceRequest && summary.status != .draft {
                let goodsOnly = try record.isIntraCommunityGoodsOnly()
                taxDocumentRequired = !goodsOnly || (sum?.withReceipt ?? 0) > 0
            }
            states.append(DocumentState(
                summary: summary,
                settlement: settlement,
                paid: MinorUnits.money(paidUnits, currency),
                outstanding: MinorUnits.money(outstandingUnits, currency),
                isOverdue: overdue,
                daysOverdue: overdue ? today.days(since: summary.dueDate) : 0,
                taxDocumentRequired: taxDocumentRequired,
                taxDocumentIssued: summary.kind == .advanceRequest && incoming > 0 && (sum?.missingReceipts ?? 0) == 0,
                deductedInFinal: summary.kind == .advanceRequest && !deductions.isEmpty,
                deductedBy: deductions,
                closure: closure))
        }
        return states
    }
}
