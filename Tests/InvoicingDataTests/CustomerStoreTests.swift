import Foundation
import Testing
import InvoicingCore
@testable import InvoicingData

@Suite struct CustomerStoreTests {
    @Test func savesFetchesAndSearches() throws {
        let database = try Fixtures.prepared()
        let store = CustomerStore(database)
        let fetched = try store.customer(id: "cust-cz")
        #expect(fetched == Fixtures.czechCustomer())
        #expect(try store.all().map(\.id) == ["cust-de", "cust-cz"])
        // Case and diacritics do not matter; name, city, DIČ, IČO and e-mail are searched.
        #expect(try store.search("odberatel").map(\.id) == ["cust-cz"])
        #expect(try store.search("BRNO").map(\.id) == ["cust-cz"])
        #expect(try store.search("DE1234").map(\.id) == ["cust-de"])
        #expect(try store.search("fakturace@").map(\.id) == ["cust-cz"])
        #expect(try store.search("   ").count == 2)
        #expect(try store.search("nobody").isEmpty)
    }

    @Test func updateKeepsCreatedAtAndWritesAudit() throws {
        let database = try Fixtures.prepared()
        let store = CustomerStore(database)
        var customer = Fixtures.czechCustomer()
        customer.paymentTermDays = 30
        customer.notes = "Platí pozdě."
        let later = Fixtures.now.addingTimeInterval(3600)
        try store.save(customer, now: later)
        #expect(try store.customer(id: "cust-cz") == customer)
        let events = try AuditLog(database).events(entity: "customer", id: "cust-cz")
        #expect(events.map(\.action) == ["create", "update"])
        #expect(events.map(\.at) == ["2026-11-05T05:00:00Z", "2026-11-05T06:00:00Z"])
    }

    @Test func archiveHidesAndDeleteNeedsNoDocuments() throws {
        let database = try Fixtures.prepared()
        let store = CustomerStore(database)
        try store.archive(id: "cust-de", now: Fixtures.now)
        #expect(try store.all().map(\.id) == ["cust-cz"])
        #expect(try store.all(includeArchived: true).count == 2)
        #expect(try store.search("beispiel").isEmpty)
        try store.unarchive(id: "cust-de", now: Fixtures.now)
        #expect(try store.all().count == 2)

        let documents = DocumentStore(database)
        try documents.saveDraft(Fixtures.czkDraft(), now: Fixtures.now)
        #expect(throws: DataError.customerHasDocuments("cust-cz")) { try store.delete(id: "cust-cz") }
        try store.delete(id: "cust-de")
        #expect(try store.customer(id: "cust-de") == nil)
        #expect(throws: DataError.customerNotFound("cust-de")) { try store.archive(id: "cust-de") }
    }
}
