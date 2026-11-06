import Foundation
import GRDB
import Testing
import InvoicingCore
@testable import InvoicingData

@Suite struct SchemaTests {
    @Test func migrationCreatesEveryTable() throws {
        let database = try AppDatabase()
        let tables = ["companyProfile", "customer", "numberSeries", "document", "documentPayment", "exchangeRate",
                      "bankStatement", "bankTransaction", "advanceDeduction", "documentClosure", "auditEvent", "documentPDF",
                      "paidAdvance", "appState", "stockItem", "stockMovement", "documentLineStock", "monthExport", "clientNote", "repairUnlock", "documentPDFHistory"]
        for table in tables {
            let exists = try database.queue.read { db in try db.tableExists(table) }
            #expect(exists, "missing table \(table)")
        }
        #expect(InvoicingData.schemaVersion == 9)
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

    @Test func upgradingAV1DatabaseKeepsItsRows() throws {
        // A database written by the first release (schema v1) is migrated in place; nothing is dropped.
        let queue = try DatabaseQueue()
        let migrator = Schema.migrator
        try migrator.migrate(queue, upTo: "v1")
        // Values are read inside the closures and checked outside: a closure whose only statements are
        // `#expect(try …)` is inferred non-throwing and does not compile.
        let hadPDFTable = try queue.write { db -> Bool in
            try db.execute(sql: "INSERT INTO auditEvent (at, entity, entityID, action) VALUES (?, ?, ?, ?)",
                           arguments: ["2026-11-05T10:00:00Z", "document", "doc-1", "create"])
            return try db.tableExists("documentPDF")
        }
        #expect(!hadPDFTable)
        try migrator.migrate(queue)
        let (completed, hasPDFTable, keptRows) = try queue.read { db -> (Bool, Bool, Int?) in
            let completed = try migrator.hasCompletedMigrations(db)
            let hasPDFTable = try db.tableExists("documentPDF")
            let keptRows = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM auditEvent WHERE entityID = 'doc-1'")
            return (completed, hasPDFTable, keptRows)
        }
        #expect(completed)
        #expect(hasPDFTable)
        #expect(keptRows == 1)
    }

    @Test func upgradingAV2DatabaseAddsThePaidAdvanceColumnsAsNull() throws {
        // v3 (ADR 0012) adds two nullable document columns and the paidAdvance table; an issued row of v2 keeps
        // its values and reads NULL in both columns (the frozen trigger never fires for a column added by ALTER).
        let queue = try DatabaseQueue()
        let migrator = Schema.migrator
        try migrator.migrate(queue, upTo: "v2")
        try queue.write { db in
            try db.execute(sql: """
                INSERT INTO document (id, kind, status, number, customerName, issueDate, dueDate, currency, amountDue, snapshot,
                                      createdAt, updatedAt)
                VALUES ('doc-old', 'invoice', 'issued', 'FV-2026-001', 'Beispiel GmbH', '2026-11-05', '2026-11-19', 'EUR', 100000, '{}',
                        '2026-11-05T10:00:00Z', '2026-11-05T10:00:00Z')
                """)
        }
        try migrator.migrate(queue)
        let (hasTable, paidInAdvance, treatments, amountDue) = try queue.read { db -> (Bool, Int64?, String?, Int64?) in
            // fetchOne reads NULL as nil.
            let paidInAdvance = try Int64.fetchOne(db, sql: "SELECT paidInAdvance FROM document WHERE id = 'doc-old'")
            let treatments = try String.fetchOne(db, sql: "SELECT treatments FROM document WHERE id = 'doc-old'")
            let amountDue = try Int64.fetchOne(db, sql: "SELECT amountDue FROM document WHERE id = 'doc-old'")
            return (try db.tableExists("paidAdvance"), paidInAdvance, treatments, amountDue)
        }
        #expect(hasTable)
        #expect(paidInAdvance == nil)
        #expect(treatments == nil)
        #expect(amountDue == 100000)
    }

    @Test func upgradingAV3DatabaseKeepsTheDatesOfSavedDrafts() throws {
        // v4 (docs-28) adds the set-by-hand flag: a draft saved before keeps the date it shows (flag on), an
        // issued row reads off, and a row inserted after the migration floats by default.
        let queue = try DatabaseQueue()
        let migrator = Schema.migrator
        try migrator.migrate(queue, upTo: "v3")
        try queue.write { db in
            for (id, status, number) in [("doc-draft", "draft", nil), ("doc-issued", "issued", "FV-2026-001")] as [(String, String, String?)] {
                try db.execute(sql: """
                    INSERT INTO document (id, kind, status, number, customerName, issueDate, dueDate, currency, snapshot,
                                          createdAt, updatedAt)
                    VALUES (?, 'invoice', ?, ?, 'Beispiel GmbH', '2026-11-05', '2026-11-19', 'EUR', '{}',
                            '2026-11-05T10:00:00Z', '2026-11-05T10:00:00Z')
                    """, arguments: [id, status, number])
            }
        }
        try migrator.migrate(queue)
        let (draft, issued) = try queue.read { db -> (Bool?, Bool?) in
            (try Bool.fetchOne(db, sql: "SELECT issueDateSetByHand FROM document WHERE id = 'doc-draft'"),
             try Bool.fetchOne(db, sql: "SELECT issueDateSetByHand FROM document WHERE id = 'doc-issued'"))
        }
        #expect(draft == true)
        #expect(issued == false)
        // The tax point's flag starts off: a draft saved before tells an explicit tax point by its other day.
        let taxPoint = try queue.read { db in try Bool.fetchOne(db, sql: "SELECT taxPointSetByHand FROM document WHERE id = 'doc-draft'") }
        #expect(taxPoint == false)
        try queue.write { db in
            try db.execute(sql: """
                INSERT INTO document (id, kind, status, customerName, issueDate, dueDate, currency, snapshot, createdAt, updatedAt)
                VALUES ('doc-new', 'invoice', 'draft', 'Beispiel GmbH', '2026-11-06', '2026-11-20', 'EUR', '{}',
                        '2026-11-06T10:00:00Z', '2026-11-06T10:00:00Z')
                """)
        }
        let fresh = try queue.read { db in try Bool.fetchOne(db, sql: "SELECT issueDateSetByHand FROM document WHERE id = 'doc-new'") }
        #expect(fresh == false)
    }
}
