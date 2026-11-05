import Foundation
import GRDB
import Testing
import InvoicingCore
@testable import InvoicingData

@Suite struct SchemaTests {
    @Test func migrationCreatesEveryTable() throws {
        let database = try AppDatabase()
        let tables = ["companyProfile", "customer", "numberSeries", "document", "documentPayment", "exchangeRate",
                      "bankStatement", "bankTransaction", "advanceDeduction", "documentClosure", "auditEvent", "documentPDF"]
        for table in tables {
            let exists = try database.queue.read { db in try db.tableExists(table) }
            #expect(exists, "missing table \(table)")
        }
        #expect(InvoicingData.schemaVersion == 2)
        let foreignKeys = try database.queue.read { db in try Bool.fetchOne(db, sql: "PRAGMA foreign_keys") }
        #expect(foreignKeys == true)
    }

    @Test func openingAFileTwiceKeepsTheData() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("fa-mac-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("fa.sqlite")
        do {
            let database = try AppDatabase(at: url)
            try ProfileStore(database).save(Fixtures.profile, now: Fixtures.now)
        }
        let reopened = try AppDatabase(at: url)
        let profile = try ProfileStore(reopened).load()
        #expect(profile == Fixtures.profile)
        // Rollback-journal mode: the database is one file, no -wal sidecar.
        #expect(!FileManager.default.fileExists(atPath: url.path + "-wal"))
    }

    @Test func timestampsAreISO8601InUTC() {
        #expect(Timestamps.string(Fixtures.now) == "2026-11-05T05:00:00Z")
    }

    @Test func minorUnitsRoundTrip() throws {
        #expect(try MinorUnits.of(Fixtures.d("12100"), .czk) == 1_210_000)
        #expect(try MinorUnits.of(Fixtures.d("0.35"), .eur) == 35)
        #expect(try MinorUnits.of(Fixtures.d("1384.5"), Currency(code: "JPY")) == 1385)
        #expect(MinorUnits.money(1_210_000, .czk) == Money(Fixtures.d("12100"), .czk))
        #expect(throws: DataError.self) { try MinorUnits.of(Fixtures.d("100000000000000000"), .czk) }
    }

    @Test func aReceiptIsLinkedToOnePaymentEvenForRawSQL() throws {
        let database = try Fixtures.prepared()
        let store = DocumentStore(database)
        try Fixtures.addAdvanceSeries(database)
        let request = try Fixtures.issuedAdvance(database)
        let first = try store.recordPayment(documentID: "adv", on: Fixtures.day("2026-11-10"), amount: Money(Fixtures.d("12100"), .czk), now: Fixtures.now)
        let second = try store.recordPayment(documentID: "adv", on: Fixtures.day("2026-11-10"), amount: Money(Fixtures.d("12100"), .czk), now: Fixtures.now)
        try store.saveDraft(Document.paymentTaxDocument(id: "dd1", forAdvanceRequest: request, received: Fixtures.d("12100"), on: Fixtures.day("2026-11-10")),
                            now: Fixtures.now)
        _ = try store.attachReceipt(paymentID: first.id, documentID: "dd1", now: Fixtures.now)
        #expect(throws: DatabaseError.self) {
            try database.queue.write { db in
                try db.execute(sql: "UPDATE documentPayment SET receiptDocumentID = 'dd1' WHERE id = ?", arguments: [second.id])
            }
        }
        #expect(try store.payments(for: "adv").first { $0.id == second.id }?.receiptDocumentID == nil)
    }

    @Test func replaceCannotOverwriteAnIssuedDocumentOrALockedPayment() throws {
        let database = try Fixtures.prepared()
        let store = DocumentStore(database)
        try store.saveDraft(Fixtures.czkDraft(), now: Fixtures.now)
        try store.issue(id: "doc-cz", seriesID: "fv", now: Fixtures.now)
        let hashBefore = try database.queue.read { db in
            try String.fetchOne(db, sql: "SELECT snapshotSHA256 FROM document WHERE id = 'doc-cz'")
        }
        let columns = "(id, kind, status, number, customerName, issueDate, dueDate, currency, snapshot, createdAt, updatedAt)"
        // The same id, or a new id taking the issued number: both would remove the issued row.
        #expect(throws: DatabaseError.self) {
            try database.queue.write { db in
                try db.execute(sql: "INSERT OR REPLACE INTO document \(columns) VALUES ('doc-cz', 'invoice', 'draft', NULL, 'x', '2026-11-05', '2026-11-19', 'CZK', '{}', 't', 't')")
            }
        }
        #expect(throws: DatabaseError.self) {
            try database.queue.write { db in
                try db.execute(sql: "REPLACE INTO document \(columns) VALUES ('evil', 'invoice', 'issued', 'FV-2026-001', 'x', '2026-11-05', '2026-11-19', 'CZK', '{}', 't', 't')")
            }
        }
        let row = try #require(try database.queue.read { db in
            try Row.fetchOne(db, sql: "SELECT status, number, snapshotSHA256 FROM document WHERE id = 'doc-cz'")
        })
        let status: String = row["status"]
        let number: String? = row["number"]
        let hash: String? = row["snapshotSHA256"]
        #expect(status == "issued")
        #expect(number == "FV-2026-001")
        #expect(hash == hashBefore)
        #expect(try database.queue.read { db in try Int64.fetchOne(db, sql: "SELECT COUNT(*) FROM document WHERE id = 'evil'") } == 0)
        // Drafts are not affected.
        try database.queue.write { db in
            try db.execute(sql: "INSERT OR REPLACE INTO document \(columns) VALUES ('fresh', 'invoice', 'draft', NULL, 'x', '2026-11-05', '2026-11-19', 'CZK', '{}', 't', 't')")
        }

        // A payment whose receipt is issued cannot be replaced either.
        try Fixtures.addAdvanceSeries(database)
        let request = try Fixtures.issuedAdvance(database)
        let payment = try store.recordPayment(documentID: "adv", on: Fixtures.day("2026-11-10"), amount: Money(Fixtures.d("12100"), .czk), now: Fixtures.now)
        try store.saveDraft(Document.paymentTaxDocument(id: "dd1", forAdvanceRequest: request, received: Fixtures.d("12100"), on: Fixtures.day("2026-11-10")),
                            now: Fixtures.now)
        _ = try store.attachReceipt(paymentID: payment.id, documentID: "dd1", now: Fixtures.now)
        try store.issue(id: "dd1", seriesID: "dd", now: Fixtures.now)
        let paymentColumns = "(id, documentID, paidOn, amount, currency, receiptDocumentID, createdAt)"
        #expect(throws: DatabaseError.self) {
            try database.queue.write { db in
                try db.execute(sql: "INSERT OR REPLACE INTO documentPayment \(paymentColumns) VALUES (?, 'adv', '2026-11-10', 1, 'CZK', NULL, 't')",
                               arguments: [payment.id])
            }
        }
        #expect(throws: DatabaseError.self) {
            try database.queue.write { db in
                try db.execute(sql: "REPLACE INTO documentPayment \(paymentColumns) VALUES ('evil', 'adv', '2026-11-10', 1, 'CZK', 'dd1', 't')")
            }
        }
        let kept = try #require(try store.payments(for: "adv").first)
        #expect(kept.id == payment.id)
        #expect(kept.amount == Money(Fixtures.d("12100"), .czk))
        #expect(kept.receiptIssued)
        // New payments are not affected.
        try database.queue.write { db in
            try db.execute(sql: "INSERT OR REPLACE INTO documentPayment \(paymentColumns) VALUES ('new', 'adv', '2026-11-11', 1, 'CZK', NULL, 't')")
        }
        #expect(try store.payments(for: "adv").count == 2)
    }

    @Test func theAuditLogIsAppendOnly() throws {
        let database = try Fixtures.prepared()
        let store = DocumentStore(database)
        try store.saveDraft(Fixtures.czkDraft(), now: Fixtures.now)
        let count = try database.queue.read { db in try Int64.fetchOne(db, sql: "SELECT COUNT(*) FROM auditEvent") }
        #expect((count ?? 0) > 0)
        #expect(throws: DatabaseError.self) {
            try database.queue.write { db in try db.execute(sql: "UPDATE auditEvent SET action = 'nothing'") }
        }
        #expect(throws: DatabaseError.self) {
            try database.queue.write { db in try db.execute(sql: "DELETE FROM auditEvent") }
        }
        let after = try database.queue.read { db in try Int64.fetchOne(db, sql: "SELECT COUNT(*) FROM auditEvent WHERE action = 'nothing'") }
        #expect(after == 0)
        #expect(try database.queue.read { db in try Int64.fetchOne(db, sql: "SELECT COUNT(*) FROM auditEvent") } == count)
    }

    @Test func aPaymentRowCarriesTheSignOfItsKind() throws {
        let database = try Fixtures.prepared()
        let store = DocumentStore(database)
        try store.saveDraft(Fixtures.czkDraft(), now: Fixtures.now)
        try store.issue(id: "doc-cz", seriesID: "fv", now: Fixtures.now)
        let columns = "(id, documentID, paidOn, amount, currency, kind, createdAt)"
        // Incoming kinds must be positive, outgoing kinds negative, and the kind must be one of the four.
        for (kind, amount) in [("received", -1), ("creditIn", 0), ("refund", 1), ("creditOut", 5), ("gift", 1)] {
            #expect(throws: DatabaseError.self) {
                try database.queue.write { db in
                    try db.execute(sql: "INSERT INTO documentPayment \(columns) VALUES ('p-\(kind)', 'doc-cz', '2026-11-10', \(amount), 'CZK', '\(kind)', 't')")
                }
            }
        }
        try database.queue.write { db in
            try db.execute(sql: "INSERT INTO documentPayment \(columns) VALUES ('p-ok', 'doc-cz', '2026-11-10', -1, 'CZK', 'refund', 't')")
        }
        let payments = try store.payments(for: "doc-cz")
        #expect(payments.count == 1)
        #expect(payments.first?.kind == .refund)
        #expect(payments.first?.amount == Money(Fixtures.d("-0.01"), .czk))
    }
}
