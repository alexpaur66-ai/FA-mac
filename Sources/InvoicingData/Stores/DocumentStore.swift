import Foundation
import GRDB
import InvoicingCore

/// Which documents a list shows.
public struct DocumentFilter: Hashable, Sendable {
    public var kinds: Set<DocumentKind>?
    public var status: DocumentStatus?
    public var customerID: String?
    /// Year of the issue date.
    public var year: Int?

    public init(kinds: Set<DocumentKind>? = nil, status: DocumentStatus? = nil, customerID: String? = nil, year: Int? = nil) {
        self.kinds = kinds
        self.status = status
        self.customerID = customerID
        self.year = year
    }
}

/// How much of a document has been paid.
public struct PaymentState: Hashable, Sendable {
    public let amountDue: Money
    public let paid: Money
    public var outstanding: Money { amountDue - paid }
    /// True when the payments cover the amount due (an overpayment counts as settled).
    public var isSettled: Bool { outstanding.amount <= 0 }
}

/// Documents: drafts are editable rows, issued documents are frozen snapshots (§ 35 ZDPH) that only
/// gain payments and audit events.
public struct DocumentStore: Sendable {
    let database: AppDatabase

    public init(_ database: AppDatabase) {
        self.database = database
    }

    /// Inserts or updates a draft. The stored status is always `draft` and the number stays empty;
    /// `issue` is the only way to an issued document. Throws `documentIsFrozen` for an issued id. A draft
    /// that is the receipt of a payment (`attachReceipt`) must still match it: an edit of its kind,
    /// currency, advance or amount that breaks the link throws `receiptMismatch` or `currencyMismatch`.
    public func saveDraft(_ document: Document, now: Date = Date()) throws {
        try database.queue.write { db in
            let stamp = Timestamps.string(now)
            let existing = try DocumentRecord.fetchOne(db, key: document.id)
            if let existing, existing.status == DocumentStatus.issued.rawValue {
                throw DataError.documentIsFrozen(document.id)
            }
            var draft = document
            draft.status = .draft
            draft.number = nil
            let totals = try? DocumentTotals.compute(for: draft)
            let record = try DocumentRecord(document: draft, totals: totals, createdAt: existing?.createdAt ?? stamp, updatedAt: stamp, issuedAt: nil)
            for payment in try DocumentPaymentRecord.filter(Column("receiptDocumentID") == draft.id).fetchAll(db) {
                try Self.checkReceipt(db, payment: payment, receipt: record)
            }
            try record.save(db)
            try AuditLog.append(db, entity: "document", id: draft.id, action: existing == nil ? "create" : "update", at: stamp)
        }
    }

    /// Deletes a draft; issued documents cannot be deleted. A bank transaction matched to the draft goes
    /// back to the unmatched list, so the incoming payment does not drop out of every list.
    public func deleteDraft(id: String, now: Date = Date()) throws {
        try database.queue.write { db in
            guard let record = try DocumentRecord.fetchOne(db, key: id) else { throw DataError.documentNotFound(id) }
            guard record.status == DocumentStatus.draft.rawValue else { throw DataError.documentIsFrozen(id) }
            let stamp = Timestamps.string(now)
            for var transaction in try BankTransactionRecord.filter(Column("matchedDocumentID") == id).fetchAll(db) {
                transaction.matchedDocumentID = nil
                transaction.matchState = TransactionMatchState.unmatched.rawValue
                try transaction.update(db)
                try AuditLog.append(db, entity: "bankTransaction", id: transaction.id, action: "match",
                                    details: ["state": TransactionMatchState.unmatched.rawValue, "document": "", "reason": "draft deleted"], at: stamp)
            }
            try record.delete(db)
            try AuditLog.append(db, entity: "document", id: id, action: "delete", at: stamp)
        }
    }

    public func document(id: String) throws -> Document? {
        try database.queue.read { db in try DocumentRecord.fetchOne(db, key: id)?.decode() }
    }

    public func summary(id: String) throws -> DocumentSummary? {
        try database.queue.read { db in try DocumentRecord.fetchOne(db, key: id)?.summary() }
    }

    /// Documents matching the filter, newest issue date first.
    public func summaries(_ filter: DocumentFilter = DocumentFilter()) throws -> [DocumentSummary] {
        try database.queue.read { db in
            var request = DocumentRecord.all()
            if let kinds = filter.kinds {
                request = request.filter(kinds.map(\.rawValue).sorted().contains(Column("kind")))
            }
            if let status = filter.status {
                request = request.filter(Column("status") == status.rawValue)
            }
            if let customerID = filter.customerID {
                request = request.filter(Column("customerID") == customerID)
            }
            if let year = filter.year {
                request = request.filter(Column("issueDate") >= "\(year)-01-01" && Column("issueDate") <= "\(year)-12-31")
            }
            return try request
                .order(Column("issueDate").desc, Column("number").desc, Column("createdAt").desc)
                .fetchAll(db)
                .map { try $0.summary() }
        }
    }

    /// Issues a draft: takes the next number of the series, completes the payment instructions, checks
    /// the document with `DocumentValidator` and freezes it. Everything happens in one transaction, so a
    /// failed validation leaves the draft, the series and the audit trail untouched. The series must number
    /// the document's kind (`seriesDoesNotNumber`), and a receipt linked to a payment must match that
    /// payment exactly (`receiptMismatch`, `currencyMismatch`) before it is frozen.
    @discardableResult
    public func issue(id: String, seriesID: String, now: Date = Date()) throws -> Document {
        try database.queue.write { db in
            guard let record = try DocumentRecord.fetchOne(db, key: id) else { throw DataError.documentNotFound(id) }
            var document = try record.decode()
            guard record.status == DocumentStatus.draft.rawValue, document.status == .draft else {
                throw DataError.documentAlreadyIssued(id)
            }
            guard let seriesRecord = try NumberSeriesRecord.fetchOne(db, key: seriesID) else { throw DataError.seriesNotFound(seriesID) }
            var stored = try seriesRecord.stored()
            guard stored.numbers(document.kind) else { throw DataError.seriesDoesNotNumber(seriesID: seriesID, kind: document.kind) }
            let number = try stored.series.next(on: document.issueDate)

            document.number = number
            document.status = .issued
            if var payment = document.payment {
                let standard = PaymentInstructions.standard(for: number, bankConnection: payment.bankConnection, currency: document.currency)
                if payment.variableSymbol == nil { payment.variableSymbol = standard.variableSymbol }
                if payment.creditorReference == nil { payment.creditorReference = standard.creditorReference }
                document.payment = payment
            } else if let profile = try ProfileStore.load(db), let account = profile.bankConnection(for: document.currency) {
                document.payment = PaymentInstructions.standard(for: number, bankConnection: account, currency: document.currency)
            }

            let errors = DocumentValidator.validate(document, forIssue: true).filter(\.isError)
            guard errors.isEmpty else { throw DataError.validationFailed(errors) }
            let totals = try DocumentTotals.compute(for: document)

            let stamp = Timestamps.string(now)
            let issued = try DocumentRecord(document: document, totals: totals, createdAt: record.createdAt, updatedAt: stamp, issuedAt: stamp)
            // The issued receipt rests on its payment: check the link again, the draft may have changed since.
            for payment in try DocumentPaymentRecord.filter(Column("receiptDocumentID") == id).fetchAll(db) {
                try Self.checkReceipt(db, payment: payment, receipt: issued)
            }
            try issued.update(db)
            try NumberSeriesRecord(stored).update(db)
            try AuditLog.append(db, entity: "document", id: id, action: "issue",
                                details: ["number": number, "series": seriesID, "sha256": issued.snapshotSHA256 ?? ""], at: stamp)
            return document
        }
    }

    // MARK: Payments

    /// Records a payment against an issued document. A payment taken from a bank transaction must be in
    /// its currency, and the payments taken from one transaction never add up to more than its credit (one
    /// transfer may pay several documents, but is never counted twice); an unmatched transaction becomes
    /// matched to the document.
    @discardableResult
    public func recordPayment(documentID: String, on day: CalendarDay, amount: Money, bankTransactionID: String? = nil,
                              note: String? = nil, now: Date = Date()) throws -> DocumentPayment {
        try database.queue.write { db in
            guard let record = try DocumentRecord.fetchOne(db, key: documentID) else { throw DataError.documentNotFound(documentID) }
            guard record.status == DocumentStatus.issued.rawValue else { throw DataError.documentNotIssued(documentID) }
            let currency = Currency(code: record.currency)
            guard amount.currency == currency else { throw DataError.currencyMismatch(expected: currency, actual: amount.currency) }
            let stamp = Timestamps.string(now)
            let units = try MinorUnits.of(amount.amount, currency)
            if let bankTransactionID {
                guard var transaction = try BankTransactionRecord.fetchOne(db, key: bankTransactionID) else {
                    throw DataError.transactionNotFound(bankTransactionID)
                }
                guard transaction.currency == currency.code else {
                    throw DataError.currencyMismatch(expected: Currency(code: transaction.currency), actual: currency)
                }
                let used = try Int64.fetchOne(db, sql: "SELECT COALESCE(SUM(amount), 0) FROM documentPayment WHERE bankTransactionID = ?",
                                              arguments: [bankTransactionID]) ?? 0
                let available = max(transaction.amount - used, 0)
                guard units <= available else {
                    throw DataError.transactionOverallocated(id: bankTransactionID, available: MinorUnits.money(available, currency),
                                                             requested: MinorUnits.money(units, currency))
                }
                if transaction.matchState == TransactionMatchState.unmatched.rawValue || transaction.matchState == TransactionMatchState.ignored.rawValue {
                    transaction.matchedDocumentID = documentID
                    transaction.matchState = TransactionMatchState.manual.rawValue
                    try transaction.update(db)
                    try AuditLog.append(db, entity: "bankTransaction", id: bankTransactionID, action: "match",
                                        details: ["state": TransactionMatchState.manual.rawValue, "document": documentID], at: stamp)
                }
            }
            let payment = DocumentPaymentRecord(id: UUID().uuidString, documentID: documentID, paidOn: day.isoString,
                                                amount: units, currency: currency.code,
                                                bankTransactionID: bankTransactionID, receiptDocumentID: nil, note: note, createdAt: stamp)
            try payment.insert(db)
            try AuditLog.append(db, entity: "document", id: documentID, action: "payment",
                                details: ["amount": amount.description, "on": day.isoString], at: stamp)
            return try payment.payment(receiptIssued: false)
        }
    }

    /// Links the payment tax document `documentID` (§ 28 odst. 1 písm. d) ZDPH, built with
    /// `Document.paymentTaxDocument`) to the payment it was issued for. See `checkReceipt` for what must
    /// match; a draft receipt is checked again on every save and when it is issued. While the receipt is
    /// issued the payment is locked: the store refuses to change or delete it and triggers back that up.
    @discardableResult
    public func attachReceipt(paymentID: String, documentID: String, now: Date = Date()) throws -> DocumentPayment {
        try database.queue.write { db in
            guard var payment = try DocumentPaymentRecord.fetchOne(db, key: paymentID) else { throw DataError.paymentNotFound(paymentID) }
            if try Self.receiptIsIssued(db, payment) { throw DataError.paymentLocked(paymentID) }
            guard let receipt = try DocumentRecord.fetchOne(db, key: documentID) else { throw DataError.documentNotFound(documentID) }
            try Self.checkReceipt(db, payment: payment, receipt: receipt)
            var details = ["payment": paymentID, "receipt": documentID]
            if let replaced = payment.receiptDocumentID, replaced != documentID { details["replaced"] = replaced }
            payment.receiptDocumentID = documentID
            try payment.update(db)
            try AuditLog.append(db, entity: "document", id: payment.documentID, action: "receiptAttached",
                                details: details, at: Timestamps.string(now))
            return try payment.payment(receiptIssued: receipt.status == DocumentStatus.issued.rawValue)
        }
    }

    /// Checks that `receipt` can be the payment tax document of `payment`: a payment tax document in the
    /// payment's currency, for the advance request the payment was received on (its number and customer),
    /// for exactly the paid amount once the receipt's amounts are known, and the receipt of no other
    /// payment. Throws `receiptMismatch` or `currencyMismatch`.
    static func checkReceipt(_ db: Database, payment: DocumentPaymentRecord, receipt: DocumentRecord) throws {
        guard receipt.kind == DocumentKind.paymentTaxDocument.rawValue else {
            throw DataError.receiptMismatch(paymentID: payment.id, detail: "\(receipt.id) is \(receipt.kind), not a payment tax document")
        }
        let currency = Currency(code: payment.currency)
        guard receipt.currency == payment.currency else {
            throw DataError.currencyMismatch(expected: currency, actual: Currency(code: receipt.currency))
        }
        guard let paid = try DocumentRecord.fetchOne(db, key: payment.documentID) else { throw DataError.documentNotFound(payment.documentID) }
        guard paid.kind == DocumentKind.advanceRequest.rawValue else {
            throw DataError.receiptMismatch(paymentID: payment.id,
                                            detail: "the payment is on \(paid.number ?? paid.id), which is \(paid.kind), not an advance request")
        }
        guard let related = receipt.relatedDocumentNumber, related == paid.number else {
            throw DataError.receiptMismatch(paymentID: payment.id,
                                            detail: "\(receipt.id) is for advance \(receipt.relatedDocumentNumber ?? "none"), the payment is on \(paid.number ?? paid.id)")
        }
        guard receipt.customerID == paid.customerID else {
            throw DataError.receiptMismatch(paymentID: payment.id,
                                            detail: "\(receipt.id) is for customer \(receipt.customerName), the advance for \(paid.customerName)")
        }
        if let due = receipt.amountDue, due != payment.amount {
            throw DataError.receiptMismatch(
                paymentID: payment.id,
                detail: "the document is for \(MinorUnits.money(due, currency)), the payment is \(MinorUnits.money(payment.amount, currency))")
        }
        if let other = try String.fetchOne(db, sql: "SELECT id FROM documentPayment WHERE receiptDocumentID = ? AND id <> ?",
                                           arguments: [receipt.id, payment.id]) {
            throw DataError.receiptMismatch(paymentID: payment.id, detail: "\(receipt.id) is already the tax document of payment \(other)")
        }
    }

    public func payments(for documentID: String) throws -> [DocumentPayment] {
        try database.queue.read { db in
            try DocumentPaymentRecord.filter(Column("documentID") == documentID).order(Column("paidOn"), Column("createdAt"))
                .fetchAll(db).map { try $0.payment(receiptIssued: try Self.receiptIsIssued(db, $0)) }
        }
    }

    /// True when the payment's receipt exists and is issued.
    static func receiptIsIssued(_ db: Database, _ payment: DocumentPaymentRecord) throws -> Bool {
        guard let receiptID = payment.receiptDocumentID else { return false }
        let status = try String.fetchOne(db, sql: "SELECT status FROM document WHERE id = ?", arguments: [receiptID])
        return status == DocumentStatus.issued.rawValue
    }

    /// Amount due, paid and outstanding of an issued document.
    public func paymentState(for documentID: String) throws -> PaymentState {
        try database.queue.read { db in
            guard let record = try DocumentRecord.fetchOne(db, key: documentID) else { throw DataError.documentNotFound(documentID) }
            guard record.status == DocumentStatus.issued.rawValue, let due = record.amountDue else {
                throw DataError.documentNotIssued(documentID)
            }
            let currency = Currency(code: record.currency)
            let paid = try Int64.fetchOne(db, sql: "SELECT COALESCE(SUM(amount), 0) FROM documentPayment WHERE documentID = ?",
                                          arguments: [documentID]) ?? 0
            return PaymentState(amountDue: MinorUnits.money(due, currency), paid: MinorUnits.money(paid, currency))
        }
    }

    /// Deletes a payment; refused while its payment tax document is issued.
    public func deletePayment(id: String, now: Date = Date()) throws {
        try database.queue.write { db in
            guard let payment = try DocumentPaymentRecord.fetchOne(db, key: id) else { throw DataError.paymentNotFound(id) }
            if try Self.receiptIsIssued(db, payment) { throw DataError.paymentLocked(id) }
            try payment.delete(db)
            try AuditLog.append(db, entity: "document", id: payment.documentID, action: "paymentDeleted",
                                details: ["payment": id], at: Timestamps.string(now))
        }
    }
}
