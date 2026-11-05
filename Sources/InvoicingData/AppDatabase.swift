import Foundation
import GRDB
import InvoicingCore

/// The one database file of the app. Opening it runs the migrations; the stores do their work through
/// `queue`, GRDB's serialized access to SQLite (one writer at a time, every `write` is a transaction).
///
/// The file is a plain SQLite database in rollback-journal mode: no sidecar files, so a copy of the file
/// taken while the app is closed is a complete backup.
public final class AppDatabase: @unchecked Sendable {
    public let queue: DatabaseQueue

    /// Opens or creates the database at `url` (its folder is created when missing) and migrates it.
    public convenience init(at url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try self.init(queue: DatabaseQueue(path: url.path, configuration: Self.configuration()))
    }

    /// An in-memory database for tests and previews.
    public convenience init() throws {
        try self.init(queue: DatabaseQueue(configuration: Self.configuration()))
    }

    init(queue: DatabaseQueue) throws {
        self.queue = queue
        try Schema.migrator.migrate(queue)
    }

    static func configuration() -> Configuration {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        return configuration
    }
}
