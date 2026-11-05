import Foundation
import GRDB
import InvoicingCore

/// The company profile: one row, replaced on every save.
public struct ProfileStore: Sendable {
    let database: AppDatabase

    public init(_ database: AppDatabase) {
        self.database = database
    }

    public func load() throws -> CompanyProfile? {
        try database.queue.read { db in try Self.load(db) }
    }

    static func load(_ db: Database) throws -> CompanyProfile? {
        try CompanyProfileRecord.fetchOne(db, key: 1)?.decode()
    }

    public func save(_ profile: CompanyProfile, now: Date = Date()) throws {
        try database.queue.write { db in
            let stamp = Timestamps.string(now)
            try CompanyProfileRecord(id: 1, snapshot: try JSONCodec.encode(profile), updatedAt: stamp).save(db)
            try AuditLog.append(db, entity: "companyProfile", id: "1", action: "save", at: stamp)
        }
    }
}
