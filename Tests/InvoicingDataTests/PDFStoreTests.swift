import Foundation
import GRDB
import Testing
import InvoicingCore
@testable import InvoicingData

@Suite struct PDFStoreTests {
    @Test func storesThePDFOfAnIssuedDocumentOnce() throws {
        let database = try Fixtures.prepared()
        let store = DocumentStore(database)
        try store.saveDraft(Fixtures.czkDraft(), now: Fixtures.now)
        #expect(throws: DataError.documentNotIssued("doc-cz")) {
            try store.storePDF(documentID: "doc-cz", data: Data("draft".utf8), now: Fixtures.now)
        }
        try store.issue(id: "doc-cz", seriesID: "fv", now: Fixtures.now)
        let bytes = Data("%PDF-1.4 test".utf8)
        let stored = try store.storePDF(documentID: "doc-cz", data: bytes, now: Fixtures.now)
        #expect(stored.documentID == "doc-cz")
        #expect(stored.data == bytes)
        #expect(stored.sha256 == JSONCodec.sha256(bytes))
        #expect(stored.renderedAt == "2026-11-05T05:00:00Z")
        #expect(stored.savedPath == nil)
        #expect(stored.savedAt == nil)
        // A second render never replaces the frozen copy.
        let again = try store.storePDF(documentID: "doc-cz", data: Data("other bytes".utf8), now: Fixtures.now.addingTimeInterval(60))
        #expect(again == stored)
        #expect(try store.pdf(for: "doc-cz") == stored)
        #expect(try store.pdf(for: "missing") == nil)
        #expect(throws: DataError.documentNotFound("missing")) { try store.storePDF(documentID: "missing", data: bytes, now: Fixtures.now) }
        let actions = try AuditLog(database).events(entity: "document", id: "doc-cz").map(\.action)
        #expect(actions.filter { $0 == "pdf" }.count == 1)
    }

    @Test func remembersWhereTheFileWasSaved() throws {
        let database = try Fixtures.prepared()
        let store = DocumentStore(database)
        try store.saveDraft(Fixtures.czkDraft(), now: Fixtures.now)
        try store.issue(id: "doc-cz", seriesID: "fv", now: Fixtures.now)
        #expect(throws: DataError.pdfNotStored("doc-cz")) {
            try store.recordSavedPDF(documentID: "doc-cz", path: "/Users/sasa/Faktury/FV-2026-001.pdf", now: Fixtures.now)
        }
        try store.storePDF(documentID: "doc-cz", data: Data("%PDF".utf8), now: Fixtures.now)
        let later = Fixtures.now.addingTimeInterval(120)
        try store.recordSavedPDF(documentID: "doc-cz", path: "/Users/sasa/Faktury/2026/FV-2026-001 Odběratel s. r. o..pdf", now: later)
        let stored = try #require(try store.pdf(for: "doc-cz"))
        #expect(stored.savedPath == "/Users/sasa/Faktury/2026/FV-2026-001 Odběratel s. r. o..pdf")
        #expect(stored.savedAt == "2026-11-05T05:02:00Z")
        #expect(stored.renderedAt == "2026-11-05T05:00:00Z")
        #expect(stored.data == Data("%PDF".utf8))
        let actions = try AuditLog(database).events(entity: "document", id: "doc-cz").map(\.action)
        #expect(actions.suffix(2) == ["pdf", "pdfSaved"])
    }

    @Test func theStoredBytesAreFrozenEvenForRawSQL() throws {
        let database = try Fixtures.prepared()
        let store = DocumentStore(database)
        try store.saveDraft(Fixtures.czkDraft(), now: Fixtures.now)
        try store.issue(id: "doc-cz", seriesID: "fv", now: Fixtures.now)
        try store.storePDF(documentID: "doc-cz", data: Data("%PDF".utf8), now: Fixtures.now)
        #expect(throws: DatabaseError.self) {
            try database.queue.write { db in try db.execute(sql: "UPDATE documentPDF SET data = x'00' WHERE documentID = 'doc-cz'") }
        }
        #expect(throws: DatabaseError.self) {
            try database.queue.write { db in try db.execute(sql: "UPDATE documentPDF SET sha256 = 'x' WHERE documentID = 'doc-cz'") }
        }
        #expect(throws: DatabaseError.self) {
            try database.queue.write { db in try db.execute(sql: "DELETE FROM documentPDF WHERE documentID = 'doc-cz'") }
        }
        // The file location may change.
        try database.queue.write { db in try db.execute(sql: "UPDATE documentPDF SET savedPath = '/tmp/a.pdf' WHERE documentID = 'doc-cz'") }
        #expect(try store.pdf(for: "doc-cz")?.data == Data("%PDF".utf8))
        #expect(try store.pdf(for: "doc-cz")?.savedPath == "/tmp/a.pdf")
    }
}
