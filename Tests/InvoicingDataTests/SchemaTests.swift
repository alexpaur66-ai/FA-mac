import Foundation
import GRDB
import Testing
import InvoicingCore
@testable import InvoicingData

@Suite struct SchemaTests {
    @Test func migrationCreatesEveryTable() throws {
        let database = try AppDatabase()
        let tables = ["companyProfile", "customer", "numberSeries", "document", "documentPayment", "exchangeRate",
                      "bankStatement", "bankTransaction", "auditEvent"]
        for table in tables {
            let exists = try database.queue.read { db in try db.tableExists(table) }
            #expect(exists, "missing table \(table)")
        }
        #expect(InvoicingData.schemaVersion == 1)
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
}
