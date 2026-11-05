import Foundation
import GRDB
import InvoicingCore

// Closing events beside an issued document, and the deduction links of final invoices (ADR 0007).
extension DocumentStore {
    // MARK: Closing events (screens-flows.md §2d)

    /// Closes an issued advance request the customer will never pay. Allowed only while nothing was
    /// recorded on it and no issued final invoice deducted it; a reason is required. The document itself
    /// stays as issued; the event can be undone with `reopen`.
    public func closeAdvanceUnpaid(id: String, reason: String, now: Date = Date()) throws {
        try database.queue.write { db in
            let record = try Self.issuedRecord(db, id: id)
            guard let kind = DocumentKind(rawValue: record.kind), kind == .advanceRequest else {
                throw DataError.closureNotApplicable(id: id, kind: DocumentKind(rawValue: record.kind) ?? .invoice)
            }
            let payments = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM documentPayment WHERE documentID = ?", arguments: [id]) ?? 0
            guard payments == 0 else { throw DataError.documentHasPayments(id) }
            let deductions = try AdvanceDeductionRecord.filter(Column("advanceRequestID") == id).fetchCount(db)
            guard deductions == 0 else { throw DataError.documentIsDeducted(id) }
            try Self.close(db, record: record, kind: .closedUnpaid, reason: reason, at: Timestamps.string(now))
        }
    }

    /// Marks an issued tax document (invoice, payment tax document, final invoice) for correction by a
    /// credit note in Phase 2. It ends the overdue state in the lists; a reason is required.
    public func markForCreditNote(id: String, reason: String, now: Date = Date()) throws {
        try database.queue.write { db in
            let record = try Self.issuedRecord(db, id: id)
            guard let kind = DocumentKind(rawValue: record.kind), kind.isTaxDocument else {
                throw DataError.closureNotApplicable(id: id, kind: DocumentKind(rawValue: record.kind) ?? .advanceRequest)
            }
            try Self.close(db, record: record, kind: .markedForCreditNote, reason: reason, at: Timestamps.string(now))
        }
    }

    /// Removes the closing event of a document, with an audit event.
    public func reopen(id: String, now: Date = Date()) throws {
        try database.queue.write { db in
            guard let closure = try DocumentClosureRecord.fetchOne(db, key: id) else { throw DataError.documentNotClosed(id) }
            try closure.delete(db)
            try AuditLog.append(db, entity: "document", id: id, action: "reopen", details: ["kind": closure.kind], at: Timestamps.string(now))
        }
    }

    public func closure(for id: String) throws -> DocumentClosure? {
        try database.queue.read { db in try DocumentClosureRecord.fetchOne(db, key: id)?.closure() }
    }

    static func issuedRecord(_ db: Database, id: String) throws -> DocumentRecord {
        guard let record = try DocumentRecord.fetchOne(db, key: id) else { throw DataError.documentNotFound(id) }
        guard record.status == DocumentStatus.issued.rawValue else { throw DataError.documentNotIssued(id) }
        return record
    }

    static func close(_ db: Database, record: DocumentRecord, kind: DocumentClosureKind, reason: String, at stamp: String) throws {
        let text = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw DataError.reasonRequired }
        guard try DocumentClosureRecord.fetchOne(db, key: record.id) == nil else { throw DataError.documentAlreadyClosed(record.id) }
        try DocumentClosureRecord(documentID: record.id, kind: kind.rawValue, reason: text, closedAt: stamp).insert(db)
        try AuditLog.append(db, entity: "document", id: record.id, action: "close", details: ["kind": kind.rawValue, "reason": text], at: stamp)
    }

    // MARK: Deductions (§ 37a ZDPH)

    /// Records which payment tax documents the final invoice deducted. A number that is not in the
    /// database (a document issued before the app) is allowed and returned, so the audit event can name
    /// it; a number that is in the database must be an issued payment tax document in the final invoice's
    /// currency and for its customer, deducted by no other final invoice (`advanceAlreadyDeducted`). Other
    /// kinds return no links.
    static func linkDeductions(_ db: Database, finalInvoice: DocumentRecord, document: Document, at stamp: String) throws -> [String] {
        guard document.kind.deductsAdvances else { return [] }
        var external: [String] = []
        var seen: Set<String> = []
        for deduction in document.advanceDeductions {
            let number = deduction.documentNumber.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !number.isEmpty, seen.insert(number).inserted else { continue }
            guard let receipt = try DocumentRecord.filter(Column("number") == number).fetchOne(db) else {
                external.append(number)
                continue
            }
            guard receipt.kind == DocumentKind.paymentTaxDocument.rawValue, receipt.status == DocumentStatus.issued.rawValue else {
                throw DataError.deductedDocumentInvalid(number: number, detail: "\(receipt.kind), \(receipt.status)")
            }
            guard receipt.currency == finalInvoice.currency else {
                throw DataError.deductedDocumentInvalid(number: number, detail: "in \(receipt.currency), the final invoice is in \(finalInvoice.currency)")
            }
            if let customer = receipt.customerID, let own = finalInvoice.customerID, customer != own {
                throw DataError.deductedDocumentInvalid(number: number, detail: "for \(receipt.customerName), the final invoice is for \(finalInvoice.customerName)")
            }
            if let existing = try AdvanceDeductionRecord.filter(Column("receiptDocumentID") == receipt.id).fetchOne(db) {
                throw DataError.advanceAlreadyDeducted(receiptNumber: number, by: existing.finalInvoiceNumber)
            }
            let advanceRequestID = try String.fetchOne(db, sql: "SELECT documentID FROM documentPayment WHERE receiptDocumentID = ?",
                                                       arguments: [receipt.id])
            try AdvanceDeductionRecord(id: UUID().uuidString, finalInvoiceID: finalInvoice.id, finalInvoiceNumber: finalInvoice.number ?? "",
                                       receiptDocumentID: receipt.id, receiptNumber: number, advanceRequestID: advanceRequestID,
                                       createdAt: stamp).insert(db)
        }
        return external
    }

    /// The payment tax documents an issued final invoice deducted, by receipt number.
    public func deductions(ofFinalInvoice id: String) throws -> [AdvanceDeductionLink] {
        try database.queue.read { db in
            try AdvanceDeductionRecord.filter(Column("finalInvoiceID") == id).order(Column("receiptNumber")).fetchAll(db).map { $0.link() }
        }
    }

    /// The final invoice that deducted a payment tax document, if any.
    public func deduction(ofReceipt id: String) throws -> AdvanceDeductionLink? {
        try database.queue.read { db in
            try AdvanceDeductionRecord.filter(Column("receiptDocumentID") == id).fetchOne(db)?.link()
        }
    }

    /// The deductions of the receipts of an advance request, by final invoice number.
    public func deductions(ofAdvanceRequest id: String) throws -> [AdvanceDeductionLink] {
        try database.queue.read { db in
            try AdvanceDeductionRecord.filter(Column("advanceRequestID") == id).order(Column("finalInvoiceNumber"), Column("receiptNumber"))
                .fetchAll(db).map { $0.link() }
        }
    }
}
