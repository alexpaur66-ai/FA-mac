import Foundation
import GRDB
import InvoicingCore

/// Imported bank statements and their transactions (v0.2 bank import; the tables and the store exist so
/// the schema is complete from the first release).
public struct StatementStore: Sendable {
    let database: AppDatabase

    public init(_ database: AppDatabase) {
        self.database = database
    }

    /// Stores a statement with its transactions in one transaction. Refuses a file that was imported
    /// before (same SHA-256) and transactions in another currency than the statement.
    public func importStatement(_ statement: BankStatement, transactions: [BankTransaction], now: Date = Date()) throws {
        try database.queue.write { db in
            if let hash = statement.fileSHA256,
               try BankStatementRecord.filter(Column("fileSHA256") == hash).fetchCount(db) > 0 {
                throw DataError.duplicateStatement(fileSHA256: hash)
            }
            for transaction in transactions {
                guard transaction.statementID == statement.id else {
                    throw DataError.statementNotFound(transaction.statementID)
                }
                guard transaction.amount.currency == statement.currency else {
                    throw DataError.currencyMismatch(expected: statement.currency, actual: transaction.amount.currency)
                }
            }
            let stamp = Timestamps.string(now)
            try BankStatementRecord(statement, importedAt: stamp).insert(db)
            for transaction in transactions {
                try BankTransactionRecord(transaction).insert(db)
            }
            try AuditLog.append(db, entity: "bankStatement", id: statement.id, action: "import",
                                details: ["transactions": String(transactions.count), "format": statement.format.rawValue], at: stamp)
        }
    }

    /// Statements, newest period first.
    public func statements() throws -> [BankStatement] {
        try database.queue.read { db in
            try BankStatementRecord.order(Column("periodTo").desc, Column("importedAt").desc).fetchAll(db).map { try $0.statement() }
        }
    }

    public func statement(id: String) throws -> BankStatement? {
        try database.queue.read { db in try BankStatementRecord.fetchOne(db, key: id)?.statement() }
    }

    public func transactions(in statementID: String) throws -> [BankTransaction] {
        try database.queue.read { db in
            try BankTransactionRecord.filter(Column("statementID") == statementID).order(Column("bookedOn"), Column("id"))
                .fetchAll(db).map { try $0.transaction() }
        }
    }

    /// Incoming payments not yet matched to a document, oldest first.
    public func unmatchedIncoming() throws -> [BankTransaction] {
        try database.queue.read { db in
            try BankTransactionRecord
                .filter(Column("matchState") == TransactionMatchState.unmatched.rawValue && Column("amount") > 0)
                .order(Column("bookedOn"), Column("id"))
                .fetchAll(db)
                .map { try $0.transaction() }
        }
    }

    /// Transactions matched to a document.
    public func transactions(matchedTo documentID: String) throws -> [BankTransaction] {
        try database.queue.read { db in
            try BankTransactionRecord.filter(Column("matchedDocumentID") == documentID).order(Column("bookedOn")).fetchAll(db)
                .map { try $0.transaction() }
        }
    }

    /// Records the match of a transaction: `documentID` nil with `.ignored` or `.unmatched`, a document id
    /// with `.automatic` or `.manual`.
    public func setMatch(transactionID: String, documentID: String?, state: TransactionMatchState, now: Date = Date()) throws {
        try database.queue.write { db in
            guard var record = try BankTransactionRecord.fetchOne(db, key: transactionID) else {
                throw DataError.transactionNotFound(transactionID)
            }
            if let documentID {
                guard try DocumentRecord.exists(db, key: documentID) else { throw DataError.documentNotFound(documentID) }
            }
            record.matchedDocumentID = documentID
            record.matchState = state.rawValue
            try record.update(db)
            try AuditLog.append(db, entity: "bankTransaction", id: transactionID, action: "match",
                                details: ["state": state.rawValue, "document": documentID ?? ""], at: Timestamps.string(now))
        }
    }

    /// Deletes a statement and its transactions; refused while any transaction is matched to a document.
    public func deleteStatement(id: String, now: Date = Date()) throws {
        try database.queue.write { db in
            guard try BankStatementRecord.exists(db, key: id) else { throw DataError.statementNotFound(id) }
            let matched = try BankTransactionRecord
                .filter(Column("statementID") == id && Column("matchedDocumentID") != nil)
                .fetchCount(db)
            guard matched == 0 else { throw DataError.statementHasMatchedTransactions(id: id, count: matched) }
            try BankStatementRecord.deleteOne(db, key: id)
            try AuditLog.append(db, entity: "bankStatement", id: id, action: "delete", at: Timestamps.string(now))
        }
    }
}
