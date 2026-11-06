import Foundation
import GRDB
import Testing
import InvoicingCore
@testable import InvoicingData

@Suite struct RepairStoreTests {
    private func issuedInvoice(_ database: AppDatabase) throws -> Document {
        let documents = DocumentStore(database)
        try documents.saveDraft(Fixtures.czkDraft(), now: Fixtures.now)
        return try documents.issue(id: "doc-cz", seriesID: "fv", now: Fixtures.now)
    }

    private func movedParty() -> Party {
        var party = Fixtures.czechParty
        party.address.street = "Nová 5"
        return party
    }

    @Test func aRepairChangesTheDocumentAndLogsEachField() throws {
        let database = try Fixtures.prepared()
        let document = try issuedInvoice(database)
        var repair = DocumentHeaderRepair(document)
        repair.customer = movedParty()
        repair.dueDate = Fixtures.day("2026-11-30")
        let later = Fixtures.now.addingTimeInterval(3600)
        let result = try RepairStore(database).repair(documentID: "doc-cz", repair: repair, reason: " Wrong address ", pdf: nil, now: later)
        #expect(result.changes.map(\.field) == [.customerAddress, .dueDate])
        #expect(result.before == DocumentHeaderRepair(document))

        let documents = DocumentStore(database)
        let stored = try #require(try documents.document(id: "doc-cz"))
        #expect(stored.customer.address.street == "Nová 5")
        #expect(stored.dueDate == Fixtures.day("2026-11-30"))
        #expect(stored.number == document.number)
        #expect(stored.lines == document.lines)
        #expect(try documents.verifyIntegrity(id: "doc-cz"))

        let repairs = try AuditLog(database).events(entity: "document", id: "doc-cz").filter { $0.action == "repair" }
        #expect(repairs.count == 2)
        let address = try #require(repairs.first)
        #expect(address.details?["field"] == "customerAddress")
        #expect(address.details?["old"] == "Krátká 1, 602 00 Brno, CZ")
        #expect(address.details?["new"] == "Nová 5, 602 00 Brno, CZ")
        #expect(address.details?["reason"] == "Wrong address")
        #expect(repairs.last?.details?["new"] == "2026-11-30")
    }

    @Test func outsideARepairAnIssuedDocumentStaysFrozen() throws {
        let database = try Fixtures.prepared()
        _ = try issuedInvoice(database)
        var repair = DocumentHeaderRepair(try #require(try DocumentStore(database).document(id: "doc-cz")))
        repair.note = "Paid by card"
        try RepairStore(database).repair(documentID: "doc-cz", repair: repair, reason: "Note missing", pdf: nil)
        // The lock is closed again: a plain write is refused as before.
        #expect(throws: (any Error).self) {
            try database.queue.write { db in
                try db.execute(sql: "UPDATE document SET dueDate = '2030-01-01' WHERE id = 'doc-cz'")
            }
        }
        let open = try database.queue.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM repairUnlock") }
        #expect(open == 0)
    }

    @Test func aRepairNeedsAReasonAndAChange() throws {
        let database = try Fixtures.prepared()
        let document = try issuedInvoice(database)
        let store = RepairStore(database)
        var repair = DocumentHeaderRepair(document)
        repair.note = "x"
        #expect(throws: RepairError.reasonRequired) {
            try store.repair(documentID: "doc-cz", repair: repair, reason: "  ", pdf: nil)
        }
        #expect(throws: RepairError.nothingChanged) {
            try store.repair(documentID: "doc-cz", repair: DocumentHeaderRepair(document), reason: "Typo", pdf: nil)
        }
        try DocumentStore(database).saveDraft(Fixtures.czkDraft(id: "draft"), now: Fixtures.now)
        #expect(throws: DataError.documentNotIssued("draft")) {
            try store.repair(documentID: "draft", repair: repair, reason: "Typo", pdf: nil)
        }
    }

    @Test func anUntouchedNoteKeepsItsBlanksAndIsNotLogged() throws {
        let database = try Fixtures.prepared()
        let documents = DocumentStore(database)
        var draft = Fixtures.czkDraft()
        draft.note = "Thanks\n"
        draft.orderReference = " PO-7 "
        try documents.saveDraft(draft, now: Fixtures.now)
        let document = try documents.issue(id: "doc-cz", seriesID: "fv", now: Fixtures.now)
        let store = RepairStore(database)
        // The sheet saved with no edits: the text fields come back as stored.
        #expect(throws: RepairError.nothingChanged) {
            try store.repair(documentID: "doc-cz", repair: DocumentHeaderRepair(document), reason: "Typo", pdf: nil)
        }
        var repair = DocumentHeaderRepair(document)
        repair.dueDate = Fixtures.day("2026-11-30")
        let result = try store.repair(documentID: "doc-cz", repair: repair, reason: "Wrong due date", pdf: nil,
                                      now: Fixtures.now.addingTimeInterval(60))
        #expect(result.changes.map(\.field) == [.dueDate])
        let stored = try #require(try documents.document(id: "doc-cz"))
        #expect(stored.note == "Thanks\n")
        #expect(stored.orderReference == " PO-7 ")
    }

    @Test func undoTakesBackOnlyItsOwnFields() throws {
        let database = try Fixtures.prepared()
        let document = try issuedInvoice(database)
        let store = RepairStore(database)
        var dueDate = DocumentHeaderRepair(document)
        dueDate.dueDate = Fixtures.day("2026-11-30")
        let first = try store.repair(documentID: "doc-cz", repair: dueDate, reason: "Wrong due date", pdf: nil,
                                     now: Fixtures.now.addingTimeInterval(60))
        var client = try store.header(documentID: "doc-cz")
        client.customer = movedParty()
        try store.repair(documentID: "doc-cz", repair: client, reason: "Wrong address", pdf: nil,
                         now: Fixtures.now.addingTimeInterval(120))
        // Undo of the first repair: the due date goes back, the later address stays.
        let undo = first.before.restoring(Set(first.changes.map(\.field)), onto: try store.header(documentID: "doc-cz"))
        let undone = try store.repair(documentID: "doc-cz", repair: undo, reason: "Undo: Wrong due date", pdf: nil,
                                      now: Fixtures.now.addingTimeInterval(180))
        #expect(undone.changes.map(\.field) == [.dueDate])
        #expect(undone.document.dueDate == document.dueDate)
        #expect(undone.document.customer.address.street == "Nová 5")
    }

    @Test func aRepairThatBreaksTheDocumentIsRefused() throws {
        let database = try Fixtures.prepared()
        let documents = DocumentStore(database)
        try documents.saveDraft(Fixtures.eurDraft(), now: Fixtures.now)
        let document = try documents.issue(id: "doc-eu", seriesID: "fv", now: Fixtures.now)
        var repair = DocumentHeaderRepair(document)
        // A reverse-charge invoice needs the client's VAT ID.
        repair.customer.vatIdentifier = nil
        var refused = false
        do {
            try RepairStore(database).repair(documentID: "doc-eu", repair: repair, reason: "Typo", pdf: nil)
        } catch DataError.validationFailed(let issues) {
            refused = !issues.isEmpty
        }
        #expect(refused)
        #expect(try documents.document(id: "doc-eu")?.customer.vatIdentifier != nil)
    }

    @Test func aRepairedPDFKeepsTheOldBytes() throws {
        let database = try Fixtures.prepared()
        let document = try issuedInvoice(database)
        let documents = DocumentStore(database)
        let old = try documents.storePDF(documentID: "doc-cz", data: Data("old".utf8), now: Fixtures.now)
        var repair = DocumentHeaderRepair(document)
        repair.customer = movedParty()
        let store = RepairStore(database)
        try store.repair(documentID: "doc-cz", repair: repair, reason: "Wrong address", pdf: Data("new".utf8),
                         now: Fixtures.now.addingTimeInterval(60))
        let stored = try #require(try documents.pdf(for: "doc-cz"))
        #expect(stored.data == Data("new".utf8))
        #expect(stored.sha256 != old.sha256)
        #expect(try store.replacedPDFCount(documentID: "doc-cz") == 1)
        let kept = try database.queue.read { db in
            try Data.fetchOne(db, sql: "SELECT data FROM documentPDFHistory WHERE documentID = 'doc-cz'")
        }
        #expect(kept == Data("old".utf8))
        let actions = try AuditLog(database).events(entity: "document", id: "doc-cz").map(\.action)
        #expect(actions.contains("pdfReplaced"))
        // The history only grows.
        #expect(throws: (any Error).self) {
            try database.queue.write { db in try db.execute(sql: "DELETE FROM documentPDFHistory") }
        }
    }

    @Test func aRepairedDocumentShowsAsChangedAfterExport() throws {
        let database = try Fixtures.prepared()
        let document = try issuedInvoice(database)
        let exports = ExportStore(database)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("fa-mac-repair-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let november = Fixtures.day("2026-11-01")
        try exports.write(try exports.data(month: november, today: Fixtures.day("2026-11-15")), to: folder, now: Fixtures.now)
        #expect(try exports.changedAfterExport().isEmpty)
        var repair = DocumentHeaderRepair(document)
        repair.customer = movedParty()
        try RepairStore(database).repair(documentID: "doc-cz", repair: repair, reason: "Wrong address", pdf: nil,
                                         now: Fixtures.now.addingTimeInterval(60))
        #expect(try exports.changedAfterExport().map(\.changedCount) == [1])
    }
}
