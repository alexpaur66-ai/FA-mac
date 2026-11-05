import Foundation
import GRDB
import InvoicingCore

/// Append-only trail of what changed: every store writes an event in the same transaction as the change.
public struct AuditLog: Sendable {
    let database: AppDatabase

    public init(_ database: AppDatabase) {
        self.database = database
    }

    static func append(_ db: Database, entity: String, id: String, action: String, details: [String: String]? = nil, at: String) throws {
        var event = AuditEventRecord(id: nil, at: at, entity: entity, entityID: id, action: action,
                                     details: try details.map { try JSONCodec.encode($0) })
        try event.insert(db)
    }

    /// Events of one record, oldest first.
    public func events(entity: String, id: String) throws -> [AuditEvent] {
        try database.queue.read { db in
            try AuditEventRecord
                .filter(Column("entity") == entity && Column("entityID") == id)
                .order(Column("id"))
                .fetchAll(db)
                .map { try $0.event() }
        }
    }

    /// The most recent events of any record, newest first.
    public func recent(limit: Int = 100) throws -> [AuditEvent] {
        try database.queue.read { db in
            try AuditEventRecord.order(Column("id").desc).limit(limit).fetchAll(db).map { try $0.event() }
        }
    }
}
