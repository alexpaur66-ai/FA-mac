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
            try Self.deleteDraft(db, record, at: Timestamps.string(now), details: nil)
        }
    }

    /// Deletes a draft record inside a transaction; the caller has checked that it is a draft.
    static func deleteDraft(_ db: Database, _ record: DocumentRecord, at stamp: String, details: [String: String]?) throws {
        for var transaction in try BankTransactionRecord.filter(Column("matchedDocumentID") == record.id).fetchAll(db) {
            transaction.matchedDocumentID = nil
            transaction.matchState = TransactionMatchState.unmatched.rawValue
            try transaction.update(db)
            try AuditLog.append(db, entity: "bankTransaction", id: transaction.id, action: "match",
                                details: ["state": TransactionMatchState.unmatched.rawValue, "document": "", "reason": "draft deleted"], at: stamp)
        }
        try record.delete(db)
        try AuditLog.append(db, entity: "document", id: record.id, action: "delete", details: details, at: stamp)
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
            try Self.request(filter).fetchAll(db).map { try $0.summary() }
        }
    }

    /// The rows matching the filter, newest issue date first.
    static func request(_ filter: DocumentFilter) -> QueryInterfaceRequest<DocumentRecord> {
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
        return request.order(Column("issueDate").desc, Column("number").desc, Column("createdAt").desc)
    }

    /// Recomputes the SHA-256 of an issued document's snapshot and compares it with the stored hash
    /// (§ 35a odst. 3 ZDPH: the integrity of a stored document can be checked at any time).
    public func verifyIntegrity(id: String) throws -> Bool {
        try database.queue.read { db in
            guard let record = try DocumentRecord.fetchOne(db, key: id) else { throw DataError.documentNotFound(id) }
            guard record.status == DocumentStatus.issued.rawValue, let stored = record.snapshotSHA256 else {
                throw DataError.documentNotIssued(id)
            }
            return JSONCodec.sha256(record.snapshot) == stored
        }
    }

    /// Issues a draft: takes the next number of the series, completes the payment instructions (with the
    /// series' variable symbol prefix), checks the document with `DocumentValidator` and freezes it.
    /// Everything happens in one transaction, so a failed validation leaves the draft, the series and the
    /// audit trail untouched. The series must number the document's kind (`seriesDoesNotNumber`), and a
    /// receipt linked to a payment must match that payment exactly (`receiptMismatch`, `currencyMismatch`)
    /// before it is frozen. A final invoice records which payment tax documents it deducted
    /// (`advanceDeduction`; see `linkDeductions`), each of which one final invoice may deduct, and which
    /// payments of § 64 goods advances it settled as paid in advance (`paidAdvance`; see `linkPaidAdvances`).
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
            let prefix = stored.series.variableSymbolPrefix
            if document.kind == .paymentTaxDocument {
                // The payment it documents has been received: nothing is due, so no account, symbol or QR code.
                document.payment = nil
            } else if var payment = document.payment {
                let standard = PaymentInstructions.standard(for: number, bankConnection: payment.bankConnection, currency: document.currency,
                                                            variableSymbolPrefix: prefix)
                if payment.variableSymbol == nil { payment.variableSymbol = standard.variableSymbol }
                if payment.creditorReference == nil { payment.creditorReference = standard.creditorReference }
                document.payment = payment
            } else if let profile = try ProfileStore.load(db), let account = profile.bankConnection(for: document.currency) {
                document.payment = PaymentInstructions.standard(for: number, bankConnection: account, currency: document.currency,
                                                                variableSymbolPrefix: prefix)
            }

            let errors = DocumentValidator.validate(document, forIssue: true).filter(\.isError)
            guard errors.isEmpty else { throw DataError.validationFailed(errors) }
            let totals = try DocumentTotals.compute(for: document)

            let stamp = Timestamps.string(now)
            let issued = try DocumentRecord(document: document, totals: totals, createdAt: record.createdAt, updatedAt: stamp, issuedAt: stamp)
            // The issued receipt rests on its payment: check the link again, the draft may have changed since.
            for payment in try DocumentPaymentRecord.filter(Column("receiptDocumentID") == id).fetchAll(db) {
                try Self.checkReceipt(db, payment: payment, receipt: issued)
                // A payment a final invoice settled as paid in advance takes no tax document (ADR 0012).
                try Self.checkNotSettled(db, payment: payment)
            }
            try issued.update(db)
            try NumberSeriesRecord(stored).update(db)
            let external = try Self.linkDeductions(db, finalInvoice: issued, document: document, at: stamp)
            let externalPaid = try Self.linkPaidAdvances(db, finalInvoice: issued, document: document, at: stamp)
            var details = ["number": number, "series": seriesID, "sha256": issued.snapshotSHA256 ?? ""]
            if !external.isEmpty { details["externalDeductions"] = external.joined(separator: ",") }
            if !externalPaid.isEmpty { details["externalPaidAdvances"] = externalPaid.joined(separator: ",") }
            try AuditLog.append(db, entity: "document", id: id, action: "issue", details: details, at: stamp)
            return document
        }
    }

    // MARK: Payments

    /// Records money received against an issued document (`amount` positive). A payment taken from a bank
    /// transaction must be in its currency and come from a credit line, and the payments taken from one
    /// transaction never add up to more than it carries (one transfer may pay several documents, but is
    /// never counted twice); an unmatched transaction becomes matched to the document. `id` names the new
    /// row: the app's Undo records a deleted payment again under its old id, so the audit trail names one payment.
    @discardableResult
    public func recordPayment(documentID: String, id: String = UUID().uuidString, on day: CalendarDay, amount: Money,
                              bankTransactionID: String? = nil, note: String? = nil, now: Date = Date()) throws -> DocumentPayment {
        try database.queue.write { db in
            try Self.insertPayment(db, id: id, documentID: documentID, on: day, amount: amount, kind: .received,
                                   bankTransactionID: bankTransactionID, relatedPaymentID: nil, note: note, at: Timestamps.string(now))
        }
    }

    /// Records money paid back to the customer, usually an overpayment: `amount` is the positive sum
    /// returned, stored as a negative `refund` payment. It may not exceed what the document holds: its net
    /// paid amount or, for a final invoice whose advances exceed the supply, the credit the customer holds,
    /// and on an advance request less what final invoices settled as paid in advance (`refundExceedsAvailable`).
    /// From a bank statement it must be a debit line in the document's
    /// currency, allocated like a credit line (`transactionOverallocated`). `id` as in `recordPayment`.
    @discardableResult
    public func recordRefund(documentID: String, id: String = UUID().uuidString, on day: CalendarDay, amount: Money,
                             bankTransactionID: String? = nil, note: String? = nil, now: Date = Date()) throws -> DocumentPayment {
        try database.queue.write { db in
            try Self.insertPayment(db, id: id, documentID: documentID, on: day, amount: -amount, kind: .refund,
                                   bankTransactionID: bankTransactionID, relatedPaymentID: nil, note: note, at: Timestamps.string(now))
        }
    }

    /// Moves credit from an overpaid document to another issued document of the same customer
    /// (`creditCustomerMismatch`) in the same currency: a
    /// `creditOut` payment on the source and a `creditIn` payment on the target, each naming the other
    /// (`relatedPaymentID`). The credit may exceed neither what the source was overpaid nor what the target
    /// still owes. Returns the target's payment.
    @discardableResult
    public func applyCredit(from sourceDocumentID: String, to targetDocumentID: String, amount: Money, on day: CalendarDay,
                            note: String? = nil, now: Date = Date()) throws -> DocumentPayment {
        try database.queue.write { db in
            let source = try Self.balance(db, documentID: sourceDocumentID)
            let target = try Self.balance(db, documentID: targetDocumentID)
            // balance() found both rows; the customer of the credit must be the customer it pays for.
            let sourceRecord = try DocumentRecord.fetchOne(db, key: sourceDocumentID)
            let targetRecord = try DocumentRecord.fetchOne(db, key: targetDocumentID)
            guard let sourceRecord, let targetRecord, Self.sameCustomer(sourceRecord, targetRecord) else {
                throw DataError.creditCustomerMismatch(sourceDocumentID: sourceDocumentID, targetDocumentID: targetDocumentID)
            }
            let currency = source.amountDue.currency
            guard amount.currency == currency else { throw DataError.currencyMismatch(expected: currency, actual: amount.currency) }
            guard target.amountDue.currency == currency else {
                throw DataError.currencyMismatch(expected: currency, actual: target.amountDue.currency)
            }
            guard amount.amount > 0 else { throw DataError.invalidPaymentAmount(amount) }
            let credit = source.outstanding.isNegative ? -source.outstanding : Money.zero(currency)
            guard credit.amount >= amount.amount else {
                throw DataError.creditNotAvailable(sourceDocumentID: sourceDocumentID, available: credit, requested: amount)
            }
            guard target.outstanding.amount >= amount.amount else {
                throw DataError.creditExceedsOutstanding(targetDocumentID: targetDocumentID, outstanding: target.outstanding, requested: amount)
            }
            let stamp = Timestamps.string(now)
            let outID = UUID().uuidString
            let inID = UUID().uuidString
            _ = try Self.insertPayment(db, id: outID, documentID: sourceDocumentID, on: day, amount: -amount, kind: .creditOut,
                                       bankTransactionID: nil, relatedPaymentID: inID, note: note, at: stamp)
            return try Self.insertPayment(db, id: inID, documentID: targetDocumentID, on: day, amount: amount, kind: .creditIn,
                                          bankTransactionID: nil, relatedPaymentID: outID, note: note, at: stamp)
        }
    }

    /// True when two documents are for the same customer: the same customer id, or, when neither has one,
    /// the same customer name.
    static func sameCustomer(_ lhs: DocumentRecord, _ rhs: DocumentRecord) -> Bool {
        guard lhs.customerID == rhs.customerID else { return false }
        guard lhs.customerID == nil else { return true }
        return lhs.customerName.trimmingCharacters(in: .whitespacesAndNewlines) == rhs.customerName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Writes one payment row after the shared checks: the document is issued, not a payment tax document
    /// (`documentNotPayable`) and in the amount's currency; the amount is not zero and has the sign of its
    /// kind; a refund does not exceed what the document holds (`refundExceedsAvailable`: the net paid
    /// amount, or the credit of a final invoice whose advances exceed the supply), and a refund or credit moved
    /// away from an advance request leaves what final invoices settled as paid in advance on it (ADR 0012,
    /// `refundExceedsAvailable` too); a bank transaction, when given, is in
    /// the currency, in the same direction (a credit line for money received, a debit line for a refund) and
    /// not used up by earlier payments, allocation being checked on absolute values. An unmatched or ignored
    /// transaction becomes matched to the document.
    static func insertPayment(_ db: Database, id: String = UUID().uuidString, documentID: String, on day: CalendarDay, amount: Money,
                              kind: DocumentPaymentKind, bankTransactionID: String?, relatedPaymentID: String?,
                              note: String?, at stamp: String) throws -> DocumentPayment {
        guard let record = try DocumentRecord.fetchOne(db, key: documentID) else { throw DataError.documentNotFound(documentID) }
        guard record.status == DocumentStatus.issued.rawValue else { throw DataError.documentNotIssued(documentID) }
        // A payment tax document records money received on its advance request, where the payment is booked.
        guard record.kind != DocumentKind.paymentTaxDocument.rawValue else { throw DataError.documentNotPayable(documentID) }
        // An advance closed as unpaid takes no payments; reopen it first.
        if let closure = try DocumentClosureRecord.fetchOne(db, key: documentID), closure.kind == DocumentClosureKind.closedUnpaid.rawValue {
            throw DataError.documentAlreadyClosed(documentID)
        }
        let currency = Currency(code: record.currency)
        guard amount.currency == currency else { throw DataError.currencyMismatch(expected: currency, actual: amount.currency) }
        let units = try MinorUnits.of(amount.amount, currency)
        guard units != 0, (units > 0) == kind.isIncoming else { throw DataError.invalidPaymentAmount(amount) }
        if !kind.isIncoming, record.kind == DocumentKind.advanceRequest.rawValue {
            // Money a final invoice settled as paid in advance stays on the advance (ADR 0012): a refund or a
            // credit moved away may take only the rest.
            let settled = try Int64.fetchOne(db, sql: "SELECT COALESCE(SUM(amount), 0) FROM paidAdvance WHERE advanceRequestID = ?",
                                             arguments: [documentID]) ?? 0
            if settled > 0 {
                let held = try Int64.fetchOne(db, sql: "SELECT COALESCE(SUM(amount), 0) FROM documentPayment WHERE documentID = ?",
                                              arguments: [documentID]) ?? 0
                let available = max(held - settled, 0)
                guard -units <= available else {
                    throw DataError.refundExceedsAvailable(documentID: documentID, available: MinorUnits.money(available, currency),
                                                           requested: MinorUnits.money(-units, currency))
                }
            }
        }
        if kind == .refund {
            // What the document holds: the net paid amount, or more when the amount due is negative (a final
            // invoice whose advances exceed the supply), so that paid never drops below min(0, amount due).
            let paidUnits = try Int64.fetchOne(db, sql: "SELECT COALESCE(SUM(amount), 0) FROM documentPayment WHERE documentID = ?",
                                               arguments: [documentID]) ?? 0
            let dueUnits = record.amountDue ?? 0
            let available = max(paidUnits - min(dueUnits, 0), 0)
            guard -units <= available else {
                throw DataError.refundExceedsAvailable(documentID: documentID, available: MinorUnits.money(available, currency),
                                                       requested: MinorUnits.money(-units, currency))
            }
        }
        if let bankTransactionID {
            guard var transaction = try BankTransactionRecord.fetchOne(db, key: bankTransactionID) else {
                throw DataError.transactionNotFound(bankTransactionID)
            }
            guard transaction.currency == currency.code else {
                throw DataError.currencyMismatch(expected: Currency(code: transaction.currency), actual: currency)
            }
            guard transaction.amount != 0, (transaction.amount > 0) == (units > 0) else {
                throw DataError.transactionDirectionMismatch(id: bankTransactionID)
            }
            let used = try Int64.fetchOne(db, sql: "SELECT COALESCE(SUM(amount), 0) FROM documentPayment WHERE bankTransactionID = ?",
                                          arguments: [bankTransactionID]) ?? 0
            let available = max(abs(transaction.amount) - abs(used), 0)
            guard abs(units) <= available else {
                throw DataError.transactionOverallocated(id: bankTransactionID, available: MinorUnits.money(available, currency),
                                                         requested: MinorUnits.money(abs(units), currency))
            }
            if transaction.matchState == TransactionMatchState.unmatched.rawValue || transaction.matchState == TransactionMatchState.ignored.rawValue {
                transaction.matchedDocumentID = documentID
                transaction.matchState = TransactionMatchState.manual.rawValue
                try transaction.update(db)
                try AuditLog.append(db, entity: "bankTransaction", id: bankTransactionID, action: "match",
                                    details: ["state": TransactionMatchState.manual.rawValue, "document": documentID], at: stamp)
            }
        }
        let payment = DocumentPaymentRecord(id: id, documentID: documentID, paidOn: day.isoString, amount: units, currency: currency.code,
                                            kind: kind.rawValue, bankTransactionID: bankTransactionID, receiptDocumentID: nil,
                                            relatedPaymentID: relatedPaymentID, note: note, createdAt: stamp)
        try payment.insert(db)
        try AuditLog.append(db, entity: "document", id: documentID, action: "payment",
                            details: ["payment": id, "kind": kind.rawValue, "amount": amount.description, "on": day.isoString], at: stamp)
        return try payment.payment(receiptIssued: false)
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
            try Self.checkNotSettled(db, payment: payment)
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
        guard payment.paymentKind?.isIncoming == true else {
            throw DataError.receiptMismatch(paymentID: payment.id, detail: "a \(payment.kind) payment has no payment tax document")
        }
        guard receipt.kind == DocumentKind.paymentTaxDocument.rawValue else {
            throw DataError.receiptMismatch(paymentID: payment.id, detail: "\(receipt.id) is \(receipt.kind), not a payment tax document")
        }
        let currency = Currency(code: payment.currency)
        guard receipt.currency == payment.currency else {
            throw DataError.currencyMismatch(expected: currency, actual: Currency(code: receipt.currency))
        }
        // § 29 odst. 1 písm. h) ZDPH: a payment tax document states the day the payment was received.
        guard receipt.taxPointDate == payment.paidOn else {
            throw DataError.receiptMismatch(paymentID: payment.id,
                                            detail: "the document's tax point is \(receipt.taxPointDate ?? "missing"), the payment was received on \(payment.paidOn)")
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
        // A deducted receipt's link is frozen: it must already name the advance request of this payment.
        if let link = try AdvanceDeductionRecord.filter(Column("receiptDocumentID") == receipt.id).fetchOne(db),
           link.advanceRequestID != payment.documentID {
            throw DataError.receiptMismatch(paymentID: payment.id,
                                            detail: "\(receipt.id) is deducted by \(link.finalInvoiceNumber) without the advance \(paid.number ?? paid.id)")
        }
    }

    public func payments(for documentID: String) throws -> [DocumentPayment] {
        try database.queue.read { db in
            try DocumentPaymentRecord.filter(Column("documentID") == documentID).order(Column("paidOn"), Column("createdAt"))
                .fetchAll(db).map { try $0.payment(receiptIssued: try Self.receiptIsIssued(db, $0)) }
        }
    }

    /// The payment a payment tax document is the receipt of; nil for a receipt no payment names.
    public func payment(ofReceipt documentID: String) throws -> DocumentPayment? {
        try database.queue.read { db in
            try DocumentPaymentRecord.filter(Column("receiptDocumentID") == documentID).fetchOne(db)
                .map { try $0.payment(receiptIssued: try Self.receiptIsIssued(db, $0)) }
        }
    }

    /// True when the payment's receipt exists and is issued.
    static func receiptIsIssued(_ db: Database, _ payment: DocumentPaymentRecord) throws -> Bool {
        guard let receiptID = payment.receiptDocumentID else { return false }
        let status = try String.fetchOne(db, sql: "SELECT status FROM document WHERE id = ?", arguments: [receiptID])
        return status == DocumentStatus.issued.rawValue
    }

    /// Amount due, net paid and outstanding of an issued document.
    public func paymentState(for documentID: String) throws -> PaymentState {
        try database.queue.read { db in try Self.balance(db, documentID: documentID) }
    }

    static func balance(_ db: Database, documentID: String) throws -> PaymentState {
        guard let record = try DocumentRecord.fetchOne(db, key: documentID) else { throw DataError.documentNotFound(documentID) }
        guard record.status == DocumentStatus.issued.rawValue, let due = record.amountDue else {
            throw DataError.documentNotIssued(documentID)
        }
        let currency = Currency(code: record.currency)
        let paid = try Int64.fetchOne(db, sql: "SELECT COALESCE(SUM(amount), 0) FROM documentPayment WHERE documentID = ?",
                                      arguments: [documentID]) ?? 0
        return PaymentState(amountDue: MinorUnits.money(due, currency), paid: MinorUnits.money(paid, currency))
    }

    /// Deletes a payment; refused while its payment tax document is issued (`paymentLocked`) or once a final
    /// invoice settled it as paid in advance (`paymentSettled`). Deleting one leg of an applied
    /// credit deletes the other leg too, so both documents stay consistent. A bank transaction the payment
    /// was taken from goes back to the unmatched list once no payment is taken from it any more, when it was
    /// matched by hand to this document (as `insertPayment` does), so the money does not drop out of every list.
    /// With `deletingDraftReceipt`, the draft payment tax document created for the payment is deleted in the
    /// same transaction instead of staying behind as a receipt of nothing; the `paymentDeleted` event names the
    /// draft either way (`receiptDeleted` or `receiptKept`). The other leg of an applied credit keeps its draft
    /// receipt, and its own `paymentDeleted` event names it (`receiptKept`).
    public func deletePayment(id: String, deletingDraftReceipt: Bool = false, now: Date = Date()) throws {
        try database.queue.write { db in
            guard let payment = try DocumentPaymentRecord.fetchOne(db, key: id) else { throw DataError.paymentNotFound(id) }
            if try Self.receiptIsIssued(db, payment) { throw DataError.paymentLocked(id) }
            try Self.checkNotSettled(db, payment: payment)
            let stamp = Timestamps.string(now)
            var details = ["payment": id, "kind": payment.kind]
            if deletingDraftReceipt, let receiptID = payment.receiptDocumentID,
               let receipt = try DocumentRecord.fetchOne(db, key: receiptID), receipt.status == DocumentStatus.draft.rawValue {
                try Self.deleteDraft(db, receipt, at: stamp, details: ["reason": "payment deleted", "payment": id])
                details["receiptDeleted"] = receiptID
            } else if let receiptID = payment.receiptDocumentID {
                details["receiptKept"] = receiptID
            }
            if let relatedID = payment.relatedPaymentID, let related = try DocumentPaymentRecord.fetchOne(db, key: relatedID) {
                if try Self.receiptIsIssued(db, related) { throw DataError.relatedPaymentLocked(paymentID: id, relatedPaymentID: relatedID) }
                if try PaidAdvanceRecord.filter(Column("paymentID") == relatedID).fetchCount(db) > 0 {
                    throw DataError.relatedPaymentLocked(paymentID: id, relatedPaymentID: relatedID)
                }
                // The other leg's draft receipt stays behind (the flag is about the clicked payment's receipt); its event names it.
                var relatedDetails = ["payment": relatedID, "kind": related.kind]
                if let receiptID = related.receiptDocumentID { relatedDetails["receiptKept"] = receiptID }
                try related.delete(db)
                try AuditLog.append(db, entity: "document", id: related.documentID, action: "paymentDeleted",
                                    details: relatedDetails, at: stamp)
            }
            try payment.delete(db)
            try AuditLog.append(db, entity: "document", id: payment.documentID, action: "paymentDeleted", details: details, at: stamp)
            try Self.releaseTransaction(db, of: payment, at: stamp)
        }
    }

    /// Returns the bank transaction of a deleted payment to the unmatched list when no other payment is taken
    /// from it and it is matched by hand to the payment's document; an automatic match, or a match to another
    /// document, stays.
    static func releaseTransaction(_ db: Database, of payment: DocumentPaymentRecord, at stamp: String) throws {
        guard let transactionID = payment.bankTransactionID else { return }
        let remaining = try DocumentPaymentRecord.filter(Column("bankTransactionID") == transactionID).fetchCount(db)
        guard remaining == 0, var transaction = try BankTransactionRecord.fetchOne(db, key: transactionID),
              transaction.matchState == TransactionMatchState.manual.rawValue, transaction.matchedDocumentID == payment.documentID else { return }
        transaction.matchedDocumentID = nil
        transaction.matchState = TransactionMatchState.unmatched.rawValue
        try transaction.update(db)
        try AuditLog.append(db, entity: "bankTransaction", id: transactionID, action: "match",
                            details: ["state": TransactionMatchState.unmatched.rawValue, "document": "", "reason": "payment deleted"], at: stamp)
    }
}
