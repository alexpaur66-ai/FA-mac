import Foundation
import GRDB
import Testing
import InvoicingCore
@testable import InvoicingData

@Suite struct StatementFileTests {
    private let pdf = Data("%PDF-1.7\nstatement 10/2026".utf8)

    @Test func aPDFStatementIsStoredUntouched() throws {
        let database = try Fixtures.prepared()
        let store = StatementStore(database)
        let statement = try store.importPDF(pdf, fileName: "vypis-10-2026.pdf", iban: Fixtures.bank.iban, currency: .czk, now: Fixtures.now)
        #expect(statement.format == .pdf)
        #expect(try store.file(statementID: statement.id) == pdf)
        let listed = try store.statements()
        #expect(listed.map(\.id) == [statement.id])
        #expect(listed.first?.fileName == "vypis-10-2026.pdf")
        #expect(try store.transactions(in: statement.id).isEmpty)
    }

    @Test func theSameFileTwiceOrAnotherKindOfFileIsRefused() throws {
        let database = try Fixtures.prepared()
        let store = StatementStore(database)
        let statement = try store.importPDF(pdf, fileName: "a.pdf", iban: Fixtures.bank.iban, currency: .czk, now: Fixtures.now)
        let hash = try #require(statement.fileSHA256)
        #expect(throws: DataError.duplicateStatement(fileSHA256: hash)) {
            try store.importPDF(pdf, fileName: "b.pdf", iban: Fixtures.bank.iban, currency: .czk, now: Fixtures.now)
        }
        #expect(throws: DataError.notAPDF("c.gpc")) {
            try store.importPDF(Data("074...".utf8), fileName: "c.gpc", iban: Fixtures.bank.iban, currency: .czk, now: Fixtures.now)
        }
        #expect(try store.statements().count == 1)
    }

    @Test func deletingTheStatementDeletesItsFile() throws {
        let database = try Fixtures.prepared()
        let store = StatementStore(database)
        let statement = try store.importPDF(pdf, fileName: "a.pdf", iban: Fixtures.bank.iban, currency: .czk, now: Fixtures.now)
        try store.deleteStatement(id: statement.id, now: Fixtures.now)
        #expect(try store.file(statementID: statement.id) == nil)
        let files = try database.queue.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM bankStatementFile") }
        #expect(files == 0)
    }
}
