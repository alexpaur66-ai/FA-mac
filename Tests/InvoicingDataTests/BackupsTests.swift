import Foundation
import Testing
import InvoicingCore
@testable import InvoicingData

@Suite struct BackupsTests {
    private func temporaryFolder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("fa-mac-backups-\(UUID().uuidString)", isDirectory: true)
    }

    @Test func namesSortByTime() throws {
        let utc = try #require(TimeZone(identifier: "UTC"))
        #expect(Backups.fileName(for: Fixtures.now, timeZone: utc) == "FA backup 2026-11-05 05-00-00.sqlite")
        let later = Backups.fileName(for: Fixtures.now.addingTimeInterval(3_600 * 24 * 40), timeZone: utc)
        #expect(Backups.fileName(for: Fixtures.now, timeZone: utc) < later)
    }

    @Test func aBackupHoldsTheDataAndOpens() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let database = try Fixtures.prepared()
        let url = try Backups.make(of: database, in: folder, now: Fixtures.now)
        #expect(try Backups.list(in: folder) == [url])
        let restored = try AppDatabase(at: url)
        #expect(try ProfileStore(restored).load() == Fixtures.profile)
        #expect(try NumberSeriesStore(restored).series(id: "fv") != nil)
        // Nothing but the backup is left behind in the folder.
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).count == 1)
    }

    @Test func keepsTheNewestThirty() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let database = try Fixtures.prepared()
        var made: [URL] = []
        for day in 0..<32 {
            made.append(try Backups.make(of: database, in: folder, now: Fixtures.now.addingTimeInterval(Double(day) * 86_400)))
        }
        let kept = try Backups.list(in: folder)
        #expect(kept.count == Backups.keepCount)
        #expect(kept == Array(made.suffix(Backups.keepCount)))
    }

    @Test func twoBackupsInOneSecondKeepBoth() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let database = try Fixtures.prepared()
        let first = try Backups.make(of: database, in: folder, now: Fixtures.now)
        let second = try Backups.make(of: database, in: folder, now: Fixtures.now)
        #expect(first != second)
        #expect(try Backups.list(in: folder).map(\.lastPathComponent) == [first.lastPathComponent, second.lastPathComponent])
    }

    @Test func aMissingFolderListsNothing() throws {
        #expect(try Backups.list(in: temporaryFolder()).isEmpty)
    }
}
