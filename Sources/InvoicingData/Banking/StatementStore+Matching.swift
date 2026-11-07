import Foundation
import GRDB
import InvoicingCore

// The triage proposals of an imported statement (screens-flows.md §2f, v0.2 bank import).
extension StatementStore {
    /// The lanes and candidates for every line of the statement, as of `today` (`BankMatcher`). It reads
    /// everything in one snapshot and stores nothing.
    public func proposals(statementID: String, today: CalendarDay) throws -> [BankMatchProposal] {
        try database.queue.read { db in try Self.proposals(db, statementID: statementID, today: today) }
    }

    static func proposals(_ db: Database, statementID: String, today: CalendarDay) throws -> [BankMatchProposal] {
        guard try BankStatementRecord.exists(db, key: statementID) else { throw DataError.statementNotFound(statementID) }
        let transactions = try BankTransactionRecord.filter(Column("statementID") == statementID).fetchAll(db).map { try $0.transaction() }
        let documents = try DocumentStore.states(db, filter: DocumentFilter(status: .issued), today: today)
        let payments = try DocumentPaymentRecord
            .filter(Column("bankTransactionID") == nil && Column("kind") == DocumentPaymentKind.received.rawValue)
            .fetchAll(db)
            .map { try $0.payment(receiptIssued: try DocumentStore.receiptIsIssued(db, $0)) }
        return BankMatcher.propose(transactions, documents: documents, payments: payments, confirmedAccounts: try Self.confirmedAccounts(db))
    }

    /// Payer accounts of matched incoming lines (`BankMatcher.normalizedAccount`) → the clients of the documents
    /// they were matched to → how many lines. A payer that paid a client twice is a known account for that
    /// client; a refund sent to the account does not count.
    public func confirmedAccounts() throws -> [String: [String: Int]] {
        try database.queue.read { db in try Self.confirmedAccounts(db) }
    }

    static func confirmedAccounts(_ db: Database) throws -> [String: [String: Int]] {
        let rows = try Row.fetchAll(db, sql: """
            SELECT t.counterpartyAccount AS account, d.customerID AS customerID
            FROM bankTransaction t JOIN document d ON d.id = t.matchedDocumentID
            WHERE t.matchState IN (?, ?) AND t.amount > 0 AND t.counterpartyAccount IS NOT NULL AND d.customerID IS NOT NULL
            """, arguments: [TransactionMatchState.automatic.rawValue, TransactionMatchState.manual.rawValue])
        var accounts: [String: [String: Int]] = [:]
        for row in rows {
            let customerID: String = row["customerID"]
            guard let account = BankMatcher.normalizedAccount(row["account"]) else { continue }
            accounts[account, default: [:]][customerID, default: 0] += 1
        }
        return accounts
    }
}
