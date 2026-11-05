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
    /// `issue` is the only way to an issued document. Throws `documentIsFrozen` for an issued id.
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
            try record.save(db)
            try AuditLog.append(db, entity: "document", id: draft.id, action: existing == nil ? "create" : "update", at: stamp)
        }
    }

    /// Deletes a draft; issued documents cannot be deleted.
    public func deleteDraft(id: String, now: Date = Date()) throws {
        try database.queue.write { db in
            guard let record = try DocumentRecord.fetchOne(db, key: id) else { throw DataError.documentNotFound(id) }
            guard record.status == DocumentStatus.draft.rawValue else { throw DataError.documentIsFrozen(id) }
            try record.delete(db)
            try AuditLog.append(db, entity: "document", id: id, action: "delete", at: Timestamps.string(now))
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
    /// failed validation leaves the draft, the series and the audit trail untouched.
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
            try issued.update(db)
            try NumberSeriesRecord(stored).update(db)
            try AuditLog.append(db, entity: "document", id: id, action: "issue",
                                details: ["number": number, "series": seriesID, "sha256": issued.snapshotSHA256 ?? ""], at: stamp)
            return document
        }
    }

    // MARK: Payments

    /// Records a payment against an issued document.
    @discardableResult
    public func recordPayment(documentID: String, on day: CalendarDay, amount: Money, bankTransactionID: String? = nil,
                              note: String? = nil, now: Date = Date()) throws -> DocumentPayment {
        try database.queue.write { db in
            guard let record = try DocumentRecord.fetchOne(db, key: documentID) else { throw DataError.documentNotFound(documentID) }
            guard record.status == DocumentStatus.issued.rawValue else { throw DataError.documentNotIssued(documentID) }
            let currency = Currency(code: record.currency)
            guard amount.currency == currency else { throw DataError.currencyMismatch(expected: currency, actual: amount.currency) }
            let stamp = Timestamps.string(now)
            let payment = DocumentPaymentRecord(id: UUID().uuidString, documentID: documentID, paidOn: day.isoString,
                                                amount: try MinorUnits.of(amount.amount, currency), currency: currency.code,
                                                bankTransactionID: bankTransactionID, note: note, createdAt: stamp)
            try payment.insert(db)
            try AuditLog.append(db, entity: "document", id: documentID, action: "payment",
                                details: ["amount": amount.description, "on": day.isoString], at: stamp)
            return try payment.payment()
        }
    }

    public func payments(for documentID: String) throws -> [DocumentPayment] {
        try database.queue.read { db in
            try DocumentPaymentRecord.filter(Column("documentID") == documentID).order(Column("paidOn"), Column("createdAt"))
                .fetchAll(db).map { try $0.payment() }
        }
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

    public func deletePayment(id: String, now: Date = Date()) throws {
        try database.queue.write { db in
            guard let payment = try DocumentPaymentRecord.fetchOne(db, key: id) else { throw DataError.documentNotFound(id) }
            try payment.delete(db)
            try AuditLog.append(db, entity: "document", id: payment.documentID, action: "paymentDeleted",
                                details: ["payment": id], at: Timestamps.string(now))
        }
    }
}
