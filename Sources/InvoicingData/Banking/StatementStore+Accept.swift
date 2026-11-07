import Foundation
import GRDB
import InvoicingCore

/// What accepting a bank line did, so the triage window can undo it (`StatementStore.undo`).
public struct BankAcceptance: Hashable, Sendable {
    public let transactionID: String
    public let documentID: String
    public let paymentID: String
    /// True when the line confirmed a payment typed in by hand; false when the payment was recorded from the line.
    public let linked: Bool

    public init(transactionID: String, documentID: String, paymentID: String, linked: Bool) {
        self.transactionID = transactionID
        self.documentID = documentID
        self.paymentID = paymentID
        self.linked = linked
    }
}

/// The accept actions of the triage window (screens-flows.md §2f, v0.2 bank import). Each runs in one
/// transaction and writes audit events; a line that is matched already is refused (`bankLineResolved`).
extension StatementStore {
    /// Records the whole line as a payment of `documentID`, dated its booking day: money in becomes a received
    /// payment, money out a refund. The line is matched by hand (or `automatic`, for Accept Exact Matches).
    @discardableResult
    public func recordPayment(fromLine transactionID: String, documentID: String, automatic: Bool = false,
                              now: Date = Date()) throws -> BankAcceptance {
        try database.queue.write { db in
            try Self.recordPayment(db, fromLine: transactionID, documentID: documentID, automatic: automatic, at: Timestamps.string(now))
        }
    }

    /// Links the line to `paymentID`, a payment typed in by hand that the line confirms: no second payment is
    /// recorded. The payment must go the line's way, be in its currency, have its amount within the payment
    /// tolerance and not be linked to a line yet (`bankLineMismatch`, `paymentAlreadyLinked`).
    @discardableResult
    public func link(line transactionID: String, toPayment paymentID: String, automatic: Bool = false,
                     now: Date = Date()) throws -> BankAcceptance {
        try database.queue.write { db in
            try Self.link(db, line: transactionID, toPayment: paymentID, automatic: automatic, at: Timestamps.string(now))
        }
    }

    /// Accept Exact Matches: every Matched line gets its payment and every Already recorded line confirms its
    /// payment, in one transaction, as the proposals stand as of `today`. Returns what was done, in booking order.
    @discardableResult
    public func acceptExactMatches(statementID: String, today: CalendarDay, now: Date = Date()) throws -> [BankAcceptance] {
        try database.queue.write { db in
            let stamp = Timestamps.string(now)
            var accepted: [BankAcceptance] = []
            for proposal in try Self.proposals(db, statementID: statementID, today: today) {
                guard let candidate = proposal.candidates.first else { continue }
                switch proposal.lane {
                case .matched:
                    accepted.append(try Self.recordPayment(db, fromLine: proposal.id, documentID: candidate.documentID, automatic: true, at: stamp))
                case .alreadyRecorded:
                    guard let paymentID = candidate.paymentID else { continue }
                    accepted.append(try Self.link(db, line: proposal.id, toPayment: paymentID, automatic: true, at: stamp))
                default:
                    continue
                }
            }
            return accepted
        }
    }

    /// Takes accepted lines back, newest first, in one transaction: a payment recorded from a line is deleted
    /// (refused like any deletion while its tax document is issued or a final invoice settled it), a linked
    /// payment is unlinked and stays as typed. Each line goes back to Unmatched once no payment is taken from it.
    public func undo(_ acceptances: [BankAcceptance], now: Date = Date()) throws {
        try database.queue.write { db in
            let stamp = Timestamps.string(now)
            for acceptance in acceptances.reversed() {
                if acceptance.linked {
                    guard let payment = try DocumentPaymentRecord.fetchOne(db, key: acceptance.paymentID) else {
                        throw DataError.paymentNotFound(acceptance.paymentID)
                    }
                    guard payment.bankTransactionID == acceptance.transactionID else { continue }
                    try setLine(db, of: payment.id, to: nil)
                    try AuditLog.append(db, entity: "document", id: payment.documentID, action: "paymentUnlinked",
                                        details: ["payment": payment.id, "bankTransaction": acceptance.transactionID], at: stamp)
                } else {
                    try DocumentStore.deletePayment(db, id: acceptance.paymentID, deletingDraftReceipt: true, at: stamp)
                }
                try Self.release(db, transactionID: acceptance.transactionID, at: stamp)
            }
        }
    }

    // MARK: Inside the transaction

    /// The line, refused when it is matched already or a payment is taken from it. An ignored line may be accepted.
    private static func openLine(_ db: Database, _ transactionID: String) throws -> BankTransactionRecord {
        guard let line = try BankTransactionRecord.fetchOne(db, key: transactionID) else { throw DataError.transactionNotFound(transactionID) }
        let taken = try DocumentPaymentRecord.filter(Column("bankTransactionID") == transactionID).fetchCount(db)
        guard taken == 0, line.matchState == TransactionMatchState.unmatched.rawValue || line.matchState == TransactionMatchState.ignored.rawValue else {
            throw DataError.bankLineResolved(transactionID)
        }
        return line
    }

    private static func setMatch(_ db: Database, _ line: inout BankTransactionRecord, documentID: String, automatic: Bool,
                                 at stamp: String) throws {
        let state = automatic ? TransactionMatchState.automatic : TransactionMatchState.manual
        line.matchedDocumentID = documentID
        line.matchState = state.rawValue
        try line.update(db)
        try AuditLog.append(db, entity: "bankTransaction", id: line.id, action: "match",
                            details: ["state": state.rawValue, "document": documentID], at: stamp)
    }

    static func recordPayment(_ db: Database, fromLine transactionID: String, documentID: String, automatic: Bool,
                              at stamp: String) throws -> BankAcceptance {
        guard try DocumentRecord.exists(db, key: documentID) else { throw DataError.documentNotFound(documentID) }
        var line = try openLine(db, transactionID)
        let transaction = try line.transaction()
        // Matched first, so `insertPayment` (which matches an open line by hand) leaves the state as set here.
        try setMatch(db, &line, documentID: documentID, automatic: automatic, at: stamp)
        let kind: DocumentPaymentKind = transaction.amount.amount > 0 ? .received : .refund
        let payment = try DocumentStore.insertPayment(db, documentID: documentID, on: transaction.bookedOn, amount: transaction.amount,
                                                      kind: kind, bankTransactionID: transactionID, relatedPaymentID: nil, note: nil, at: stamp)
        return BankAcceptance(transactionID: transactionID, documentID: documentID, paymentID: payment.id, linked: false)
    }

    static func link(_ db: Database, line transactionID: String, toPayment paymentID: String, automatic: Bool,
                     at stamp: String) throws -> BankAcceptance {
        var line = try openLine(db, transactionID)
        let transaction = try line.transaction()
        guard let payment = try DocumentPaymentRecord.fetchOne(db, key: paymentID) else { throw DataError.paymentNotFound(paymentID) }
        guard payment.bankTransactionID == nil else { throw DataError.paymentAlreadyLinked(paymentID) }
        let expected: DocumentPaymentKind = transaction.amount.amount > 0 ? .received : .refund
        let paid = Money(minorUnits: payment.amount, currency: Currency(code: payment.currency))
        guard payment.kind == expected.rawValue, PaymentTolerance.matches(paid, transaction.amount) else {
            throw DataError.bankLineMismatch(transactionID: transactionID, paymentID: paymentID)
        }
        try setMatch(db, &line, documentID: payment.documentID, automatic: automatic, at: stamp)
        try setLine(db, of: paymentID, to: transactionID)
        try AuditLog.append(db, entity: "document", id: payment.documentID, action: "paymentLinked",
                            details: ["payment": paymentID, "bankTransaction": transactionID], at: stamp)
        return BankAcceptance(transactionID: transactionID, documentID: payment.documentID, paymentID: paymentID, linked: true)
    }

    /// Sets only the bank line of a payment. A plain record update would write every column, which the locks of a
    /// payment with an issued tax document or one a final invoice settled refuse; the line alone they allow (v10).
    private static func setLine(_ db: Database, of paymentID: String, to transactionID: String?) throws {
        try db.execute(sql: "UPDATE documentPayment SET bankTransactionID = ? WHERE id = ?", arguments: [transactionID, paymentID])
    }

    /// Returns the line to Unmatched when no payment is taken from it any more, however it was matched.
    private static func release(_ db: Database, transactionID: String, at stamp: String) throws {
        let taken = try DocumentPaymentRecord.filter(Column("bankTransactionID") == transactionID).fetchCount(db)
        guard taken == 0, var line = try BankTransactionRecord.fetchOne(db, key: transactionID),
              line.matchState != TransactionMatchState.unmatched.rawValue else { return }
        line.matchedDocumentID = nil
        line.matchState = TransactionMatchState.unmatched.rawValue
        try line.update(db)
        try AuditLog.append(db, entity: "bankTransaction", id: transactionID, action: "match",
                            details: ["state": TransactionMatchState.unmatched.rawValue, "document": "", "reason": "undo"], at: stamp)
    }
}
