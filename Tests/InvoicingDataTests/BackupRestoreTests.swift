import Foundation
import GRDB
import Testing
import InvoicingCore
@testable import InvoicingData

@Suite struct BackupRestoreTests {
    private func temporaryFolder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("fa-mac-restore-\(UUID().uuidString)", isDirectory: true)
    }

    private func customerCount(_ database: AppDatabase) throws -> Int {
        try database.queue.read { db -> Int in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM customer") ?? 0 }
    }

    @Test func theBackupTellsWhenAndWhatItHolds() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = try Backups.make(of: try Fixtures.prepared(), in: folder, now: Fixtures.now, appVersion: "1.0 (7)")
        let info = try Backups.inspect(url)
        #expect(info == BackupInfo(madeAt: Fixtures.now, appVersion: "1.0 (7)", documents: 0, clients: 2))
    }

    @Test func restoreReplacesTheDataAndDropsTheStamp() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let database = try Fixtures.prepared()
        let url = try Backups.make(of: database, in: folder, now: Fixtures.now, appVersion: "1.0 (7)")
        try CustomerStore(database).save(Fixtures.czechCustomer(id: "cust-3"), now: Fixtures.now)
        #expect(try customerCount(database) == 3)
        try Backups.restore(from: url, into: database)
        #expect(try customerCount(database) == 2)
        #expect(try ProfileStore(database).load() == Fixtures.profile)
        let stamps = try database.queue.read { db -> Int in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM appState WHERE key LIKE 'backup.%'") ?? 0
        }
        #expect(stamps == 0)
    }

    @Test func theBackupBeforeARestoreKeepsTheOldestBackup() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let database = try Fixtures.prepared()
        for second in 0..<Backups.keepCount {
            try Backups.make(of: database, in: folder, now: Fixtures.now.addingTimeInterval(Double(second)))
        }
        let oldest = try #require(try Backups.list(in: folder).first)
        try CustomerStore(database).save(Fixtures.czechCustomer(id: "cust-3"), now: Fixtures.now)
        try Backups.make(of: database, in: folder, now: Fixtures.now.addingTimeInterval(3_600), pruning: false)
        #expect(FileManager.default.fileExists(atPath: oldest.path))
        #expect(try Backups.list(in: folder).count == Backups.keepCount + 1)
        try Backups.restore(from: oldest, into: database)
        #expect(try customerCount(database) == 2)
    }

    @Test func aRestoreThatFailsAfterCopyingLeavesTheDataAsItWas() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let database = try Fixtures.prepared()
        let url = try Backups.make(of: database, in: folder, now: Fixtures.now)
        // A backup without appState passes inspect, but removing its stamp fails after it was copied.
        let queue = try DatabaseQueue(path: url.path)
        try queue.write { db in try db.execute(sql: "DROP TABLE appState") }
        try queue.close()
        try CustomerStore(database).save(Fixtures.czechCustomer(id: "cust-3"), now: Fixtures.now)
        #expect(throws: (any Error).self) { try Backups.restore(from: url, into: database) }
        #expect(try customerCount(database) == 3)
    }

    @Test func aFileThatIsNotABackupIsRefused() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("notes.sqlite")
        try Data("not a database".utf8).write(to: url)
        #expect(throws: BackupError.unreadable) { try Backups.inspect(url) }
        let database = try Fixtures.prepared()
        #expect(throws: BackupError.unreadable) { try Backups.restore(from: url, into: database) }
        #expect(try customerCount(database) == 2)
    }

    @Test func aBackupFromANewerVersionIsRefused() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = try Backups.make(of: try Fixtures.prepared(), in: folder, now: Fixtures.now)
        let queue = try DatabaseQueue(path: url.path)
        try queue.write { db in try db.execute(sql: "INSERT INTO grdb_migrations (identifier) VALUES ('v999')") }
        try queue.close()
        #expect(throws: BackupError.madeByNewerVersion) { try Backups.inspect(url) }
    }

    @Test func anUnopenableDataFileIsKeptAsideAndReplaced() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let backup = try Backups.make(of: try Fixtures.prepared(), in: folder.appendingPathComponent("Backups"), now: Fixtures.now)
        let dataURL = folder.appendingPathComponent("FA.sqlite")
        try Data("damaged".utf8).write(to: dataURL)
        let utc = try #require(TimeZone(identifier: "UTC"))
        let aside = try #require(try Backups.replaceUnopenableFile(at: dataURL, with: backup, now: Fixtures.now, timeZone: utc))
        #expect(aside.lastPathComponent == "FA.sqlite unopenable 2026-11-05 05-00-00")
        #expect(try Data(contentsOf: aside) == Data("damaged".utf8))
        let reopened = try AppDatabase(at: dataURL)
        #expect(try customerCount(reopened) == 2)
    }
}
