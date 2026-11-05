import GRDB
import Testing
@testable import InvoicingData

@Test("GRDB links and an in-memory database answers a query")
func grdbLinks() throws {
    let queue = try DatabaseQueue()
    let one = try queue.read { db in try Int.fetchOne(db, sql: "SELECT 1") }
    #expect(one == 1)
    #expect(InvoicingData.schemaVersion == 0)
}
