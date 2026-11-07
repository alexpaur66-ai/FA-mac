import Foundation
import GRDB
import InvoicingCore

// Statement files (screens-flows.md §2f): the PDF fallback stores a statement whose lines the app cannot
// read yet, so Sasa reads it next to the open documents and records the payments by hand.
extension StatementStore {
    /// Stores a PDF statement of the account `iban`, kept in `currency`, untouched. Refuses a file imported
    /// before (same SHA-256, `duplicateStatement`) and a file that is not a PDF (`notAPDF`).
    @discardableResult
    public func importPDF(_ data: Data, fileName: String, iban: IBAN, currency: Currency, now: Date = Date()) throws -> BankStatement {
        guard data.starts(with: Data("%PDF".utf8)) else { throw DataError.notAPDF(fileName) }
        let statement = BankStatement(iban: iban, currency: currency, format: .pdf, fileName: fileName, fileSHA256: JSONCodec.sha256(data))
        try database.queue.write { db in
            if let hash = statement.fileSHA256,
               try BankStatementRecord.filter(Column("fileSHA256") == hash).fetchCount(db) > 0 {
                throw DataError.duplicateStatement(fileSHA256: hash)
            }
            let stamp = Timestamps.string(now)
            try BankStatementRecord(statement, importedAt: stamp).insert(db)
            try db.execute(sql: "INSERT INTO bankStatementFile (statementID, data) VALUES (?, ?)", arguments: [statement.id, data])
            try AuditLog.append(db, entity: "bankStatement", id: statement.id, action: "import",
                                details: ["transactions": "0", "format": BankStatementFormat.pdf.rawValue, "file": fileName], at: stamp)
        }
        return statement
    }

    /// The stored file of a statement; nil when none was stored.
    public func file(statementID: String) throws -> Data? {
        try database.queue.read { db in
            try Data.fetchOne(db, sql: "SELECT data FROM bankStatementFile WHERE statementID = ?", arguments: [statementID])
        }
    }
}
