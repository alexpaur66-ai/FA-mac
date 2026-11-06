import Foundation
import GRDB

/// Why a file cannot be restored (screens-flows.md §2h).
public enum BackupError: Error, Equatable, Sendable {
    /// The file is not a database of this app, or SQLite finds it damaged.
    case unreadable
    /// A newer version of the app made the file; this version cannot read its data.
    case madeByNewerVersion
}

/// What a backup holds, for the preview before a restore: when it was made, by which app version, and
/// how many documents and clients it has. A file copied by hand carries no date or version.
public struct BackupInfo: Equatable, Sendable {
    public let madeAt: Date?
    public let appVersion: String?
    public let documents: Int
    public let clients: Int
}

extension Backups {
    static let madeAtKey = "backup.madeAt"
    static let appVersionKey = "backup.appVersion"

    /// Writes when the backup was made and by which app version into the backup itself, so the restore
    /// preview can show them whatever the file is renamed to.
    static func stamp(_ destination: DatabaseQueue, now: Date, appVersion: String?) throws {
        try destination.write { db in
            guard try db.tableExists("appState") else { return }
            try db.execute(sql: "INSERT OR REPLACE INTO appState (key, value) VALUES (?, ?)",
                           arguments: [madeAtKey, Timestamps.string(now)])
            if let appVersion {
                try db.execute(sql: "INSERT OR REPLACE INTO appState (key, value) VALUES (?, ?)",
                               arguments: [appVersionKey, appVersion])
            }
        }
    }

    /// Opens `url` read-only and checks that it is a sound database of this app that this version can
    /// read; throws `BackupError` when it is not.
    public static func inspect(_ url: URL) throws -> BackupInfo {
        let source = try openReadOnly(url)
        defer { try? source.close() }
        do {
            return try source.read { db in
                guard try db.tableExists("grdb_migrations") else { throw BackupError.unreadable }
                let applied = try Schema.migrator.appliedIdentifiers(db)
                guard applied.contains("v1") else { throw BackupError.unreadable }
                if try Schema.migrator.hasBeenSuperseded(db) { throw BackupError.madeByNewerVersion }
                let check = try String.fetchAll(db, sql: "PRAGMA integrity_check")
                guard check == ["ok"] else { throw BackupError.unreadable }
                let documents = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM document") ?? 0
                let clients = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM customer") ?? 0
                var madeAt: Date?
                var appVersion: String?
                if try db.tableExists("appState") {
                    let stamp = try String.fetchOne(db, sql: "SELECT value FROM appState WHERE key = ?", arguments: [madeAtKey])
                    madeAt = stamp.flatMap { try? Date($0, strategy: .iso8601) }
                    appVersion = try String.fetchOne(db, sql: "SELECT value FROM appState WHERE key = ?", arguments: [appVersionKey])
                }
                return BackupInfo(madeAt: madeAt, appVersion: appVersion, documents: documents, clients: clients)
            }
        } catch let error as BackupError {
            throw error
        } catch {
            // Not an SQLite file, or one SQLite cannot read.
            throw BackupError.unreadable
        }
    }

    /// Replaces all data in the open `database` with the backup at `url`, brought to this version's schema.
    /// The backup is first copied into a temporary file, migrated there and stripped of its stamp; only
    /// then does SQLite's online backup write that prepared copy into the open database in one step, so
    /// the app keeps its connection and a failure leaves the data as it was. The caller backs up the
    /// current data first.
    public static func restore(from url: URL, into database: AppDatabase) throws {
        _ = try inspect(url)
        let files = FileManager.default
        let prepared = files.temporaryDirectory
            .appendingPathComponent("FA restore " + UUID().uuidString + "." + nameExtension, isDirectory: false)
        defer {
            try? files.removeItem(atPath: prepared.path)
            try? files.removeItem(atPath: prepared.path + "-journal")
        }
        let copy = try DatabaseQueue(path: prepared.path, configuration: AppDatabase.configuration())
        // Closed before the file is deleted (defers run last first).
        defer { try? copy.close() }
        do {
            let source = try openReadOnly(url)
            defer { try? source.close() }
            try source.backup(to: copy)
        }
        try Schema.migrator.migrate(copy)
        try copy.write { db in
            try db.execute(sql: "DELETE FROM appState WHERE key IN (?, ?)", arguments: [madeAtKey, appVersionKey])
        }
        // The one step that changes the open database.
        try copy.backup(to: database.queue)
    }

    /// For a data file that cannot be opened (screens-flows.md §2a, Error): keeps it beside itself as
    /// "‹name› unopenable 2026-11-06 09-02-13" and puts a copy of the backup in its place. Returns where
    /// the old file went, or nil when there was none.
    @discardableResult
    public static func replaceUnopenableFile(at dataURL: URL, with backupURL: URL, now: Date = Date(),
                                             timeZone: TimeZone = .current) throws -> URL? {
        _ = try inspect(backupURL)
        let files = FileManager.default
        try files.createDirectory(at: dataURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        var aside: URL?
        if files.fileExists(atPath: dataURL.path) {
            let stamp = String(fileName(for: now, timeZone: timeZone).dropFirst(namePrefix.count).dropLast(nameExtension.count + 1))
            let target = dataURL.deletingLastPathComponent()
                .appendingPathComponent(dataURL.lastPathComponent + " unopenable " + stamp, isDirectory: false)
            try files.moveItem(at: dataURL, to: target)
            aside = target
            // A journal left beside the damaged file belongs to it, not to the restored one.
            let journal = URL(fileURLWithPath: dataURL.path + "-journal")
            if files.fileExists(atPath: journal.path) {
                try files.moveItem(at: journal, to: URL(fileURLWithPath: target.path + "-journal"))
            }
        }
        try files.copyItem(at: backupURL, to: dataURL)
        return aside
    }

    private static func openReadOnly(_ url: URL) throws -> DatabaseQueue {
        var configuration = Configuration()
        configuration.readonly = true
        do {
            return try DatabaseQueue(path: url.path, configuration: configuration)
        } catch {
            throw BackupError.unreadable
        }
    }
}
