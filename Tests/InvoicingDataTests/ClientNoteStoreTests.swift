import Foundation
import Testing
import InvoicingCore
@testable import InvoicingData

@Suite struct ClientNoteStoreTests {
    @Test func notesAreTrimmedAndListedNewestFirst() throws {
        let database = try Fixtures.prepared()
        let store = ClientNoteStore(database)
        let first = try store.add(customerID: "cust-cz", text: "  Agreed 14 days.\n", day: Fixtures.day("2026-11-03"),
                                  id: "n1", now: Fixtures.now)
        #expect(first.text == "Agreed 14 days.")
        try store.add(customerID: "cust-cz", text: "Called about the October order", day: Fixtures.day("2026-11-05"),
                      id: "n2", now: Fixtures.now)
        // Same day as n2, written later.
        try store.add(customerID: "cust-cz", text: "Sent the price list", day: Fixtures.day("2026-11-05"),
                      id: "n3", now: Fixtures.now.addingTimeInterval(60))
        try store.add(customerID: "cust-de", text: "Other client", day: Fixtures.day("2026-11-06"), id: "n4", now: Fixtures.now)
        let ids = try store.notes(customerID: "cust-cz").map(\.id)
        #expect(ids == ["n3", "n2", "n1"])
        let events = try AuditLog(database).events(entity: "clientNote", id: "n1")
        #expect(events.map(\.action) == ["create"])
    }

    @Test func anEmptyNoteOrAnUnknownClientIsRefused() throws {
        let database = try Fixtures.prepared()
        let store = ClientNoteStore(database)
        #expect(throws: ClientNoteError.textRequired) {
            try store.add(customerID: "cust-cz", text: " \n ", day: Fixtures.day("2026-11-05"))
        }
        #expect(throws: DataError.customerNotFound("nobody")) {
            try store.add(customerID: "nobody", text: "Hello", day: Fixtures.day("2026-11-05"))
        }
        #expect(try store.notes(customerID: "cust-cz").isEmpty)
    }

    @Test func anUpdateReturnsTheNoteAsItWas() throws {
        let database = try Fixtures.prepared()
        let store = ClientNoteStore(database)
        try store.add(customerID: "cust-cz", text: "First", day: Fixtures.day("2026-11-03"), id: "n1", now: Fixtures.now)
        let later = Fixtures.now.addingTimeInterval(3600)
        let before = try store.update(id: "n1", text: " Second ", day: Fixtures.day("2026-11-04"), now: later)
        #expect(before.text == "First")
        #expect(before.day == Fixtures.day("2026-11-03"))
        let after = try #require(try store.notes(customerID: "cust-cz").first)
        #expect(after.text == "Second")
        #expect(after.day == Fixtures.day("2026-11-04"))
        #expect(after.createdAt == before.createdAt)
        #expect(after.updatedAt != before.updatedAt)
        #expect(throws: ClientNoteError.textRequired) {
            try store.update(id: "n1", text: "", day: Fixtures.day("2026-11-04"))
        }
        #expect(throws: ClientNoteError.noteNotFound("gone")) {
            try store.update(id: "gone", text: "x", day: Fixtures.day("2026-11-04"))
        }
    }

    @Test func aDeletedNoteComesBackUnderItsID() throws {
        let database = try Fixtures.prepared()
        let store = ClientNoteStore(database)
        let note = try store.add(customerID: "cust-cz", text: "Keep", day: Fixtures.day("2026-11-03"), id: "n1", now: Fixtures.now)
        let deleted = try store.delete(id: "n1")
        #expect(deleted == note)
        #expect(try store.notes(customerID: "cust-cz").isEmpty)
        try store.restore(deleted)
        #expect(try store.notes(customerID: "cust-cz") == [note])
        // A second restore changes nothing.
        try store.restore(deleted)
        #expect(try store.notes(customerID: "cust-cz").count == 1)
        let actions = try AuditLog(database).events(entity: "clientNote", id: "n1").map(\.action)
        #expect(actions == ["create", "delete", "restore"])
    }

    @Test func notesGoWithTheirClient() throws {
        let database = try Fixtures.prepared()
        let store = ClientNoteStore(database)
        let note = try store.add(customerID: "cust-de", text: "Met at the fair", day: Fixtures.day("2026-11-03"), id: "n1")
        try CustomerStore(database).delete(id: "cust-de")
        #expect(try store.notes(customerID: "cust-de").isEmpty)
        // Undo of a note's delete does nothing once its client is gone.
        try store.restore(note)
        #expect(try store.notes(customerID: "cust-de").isEmpty)
    }

    @Test func theDocumentEventsAreTheOnesAClientsHistoryShows() throws {
        let database = try Fixtures.prepared()
        try Fixtures.addAdvanceSeries(database)
        let advance = try Fixtures.issuedAdvance(database)
        _ = try Fixtures.issuedReceipt(database, advance: advance)
        let store = ClientNoteStore(database)
        #expect(try store.documentEvents(documentIDs: []).isEmpty)
        let events = try store.documentEvents(documentIDs: [advance.id])
        // The draft's create and update and the receipt link stay on the document.
        #expect(events.map(\.action) == ["issue", "payment"])
        #expect(events.allSatisfy { $0.entityID == advance.id })
        let both = try store.documentEvents(documentIDs: [advance.id, "dd1"])
        #expect(both.map(\.action) == ["issue", "payment", "issue"])
    }
}
