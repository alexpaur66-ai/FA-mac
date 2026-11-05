import Foundation
import GRDB
import InvoicingCore

/// The light CRM: customers are kept as snapshots with the columns the list and the search need.
public struct CustomerStore: Sendable {
    let database: AppDatabase

    public init(_ database: AppDatabase) {
        self.database = database
    }

    /// Inserts a new customer or replaces an existing one (same id).
    public func save(_ customer: Customer, now: Date = Date()) throws {
        try database.queue.write { db in
            let stamp = Timestamps.string(now)
            let existing = try CustomerRecord.fetchOne(db, key: customer.id)
            let record = try CustomerRecord(customer: customer, createdAt: existing?.createdAt ?? stamp, updatedAt: stamp,
                                            archivedAt: existing?.archivedAt)
            try record.save(db)
            try AuditLog.append(db, entity: "customer", id: customer.id, action: existing == nil ? "create" : "update", at: stamp)
        }
    }

    public func customer(id: String) throws -> Customer? {
        try database.queue.read { db in try CustomerRecord.fetchOne(db, key: id)?.decode() }
    }

    /// Customers by name; archived ones only when asked for.
    public func all(includeArchived: Bool = false) throws -> [Customer] {
        try database.queue.read { db in
            var request = CustomerRecord.order(Column("name").collating(.localizedCaseInsensitiveCompare))
            if !includeArchived { request = request.filter(Column("archivedAt") == nil) }
            return try request.fetchAll(db).map { try $0.decode() }
        }
    }

    /// Active customers whose name, city, DIČ, IČO or e-mail contains `text`, ignoring case and diacritics.
    public func search(_ text: String) throws -> [Customer] {
        let key = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return try all() }
        return try database.queue.read { db in
            try CustomerRecord
                .filter(Column("archivedAt") == nil)
                .filter(Column("searchKey").like("%" + key + "%"))
                .order(Column("name").collating(.localizedCaseInsensitiveCompare))
                .fetchAll(db)
                .map { try $0.decode() }
        }
    }

    /// Hides the customer from lists; their documents stay.
    public func archive(id: String, now: Date = Date()) throws {
        try setArchived(id: id, archived: true, now: now)
    }

    public func unarchive(id: String, now: Date = Date()) throws {
        try setArchived(id: id, archived: false, now: now)
    }

    private func setArchived(id: String, archived: Bool, now: Date) throws {
        try database.queue.write { db in
            guard var record = try CustomerRecord.fetchOne(db, key: id) else { throw DataError.customerNotFound(id) }
            let stamp = Timestamps.string(now)
            record.archivedAt = archived ? stamp : nil
            record.updatedAt = stamp
            try record.update(db)
            try AuditLog.append(db, entity: "customer", id: id, action: archived ? "archive" : "unarchive", at: stamp)
        }
    }

    /// Removes a customer that no document refers to; otherwise throws `customerHasDocuments`.
    public func delete(id: String, now: Date = Date()) throws {
        try database.queue.write { db in
            guard try CustomerRecord.exists(db, key: id) else { throw DataError.customerNotFound(id) }
            let documents = try DocumentRecord.filter(Column("customerID") == id).fetchCount(db)
            guard documents == 0 else { throw DataError.customerHasDocuments(id) }
            try CustomerRecord.deleteOne(db, key: id)
            try AuditLog.append(db, entity: "customer", id: id, action: "delete", at: Timestamps.string(now))
        }
    }
}
