import Foundation
import GRDB
import InvoicingCore

/// Numbering series. The counter advances only inside `DocumentStore.issue`, in the same transaction as
/// the document, so a number is never skipped or used twice (§ 29 odst. 1 písm. e) ZDPH).
public struct NumberSeriesStore: Sendable {
    let database: AppDatabase

    public init(_ database: AppDatabase) {
        self.database = database
    }

    /// Inserts or replaces a series. Replacing a series that has issued numbers with a lower counter or an
    /// earlier year would reuse numbers, so the stored year and counter never move backwards, whatever the
    /// template: name, kinds, template and yearly reset stay editable, the counter carries on.
    public func save(_ stored: StoredNumberSeries, now: Date = Date()) throws {
        try database.queue.write { db in
            let existing = try NumberSeriesRecord.fetchOne(db, key: stored.id)
            var record = NumberSeriesRecord(stored)
            if let existing {
                if existing.resetsYearly && record.resetsYearly {
                    // The counter belongs to its year: keep the stored pair when it is ahead.
                    if (existing.year, existing.lastCounter) > (record.year, record.lastCounter) {
                        record.year = existing.year
                        record.lastCounter = existing.lastCounter
                        record.lastIssuedYear = existing.lastIssuedYear
                    }
                } else {
                    // A counter that does not restart yearly only grows.
                    if existing.lastCounter > record.lastCounter {
                        record.lastCounter = existing.lastCounter
                        record.lastIssuedYear = existing.lastIssuedYear
                    }
                    record.year = max(record.year, existing.year)
                }
            }
            try record.save(db)
            try AuditLog.append(db, entity: "numberSeries", id: stored.id, action: existing == nil ? "create" : "update",
                                details: ["template": record.template, "lastCounter": String(record.lastCounter)], at: Timestamps.string(now))
        }
    }

    public func series(id: String) throws -> StoredNumberSeries? {
        try database.queue.read { db in try NumberSeriesRecord.fetchOne(db, key: id)?.stored() }
    }

    public func all() throws -> [StoredNumberSeries] {
        try database.queue.read { db in
            try NumberSeriesRecord.order(Column("name")).fetchAll(db).map { try $0.stored() }
        }
    }

    /// Series that number documents of `kind`.
    public func series(for kind: DocumentKind) throws -> [StoredNumberSeries] {
        try all().filter { $0.numbers(kind) }
    }

    /// The number the next document dated `day` would get, without issuing it.
    public func peekNextNumber(seriesID: String, on day: CalendarDay) throws -> String {
        guard let stored = try series(id: seriesID) else { throw DataError.seriesNotFound(seriesID) }
        return try stored.series.peek(on: day)
    }

    public func delete(id: String, now: Date = Date()) throws {
        try database.queue.write { db in
            guard try NumberSeriesRecord.deleteOne(db, key: id) else { throw DataError.seriesNotFound(id) }
            try AuditLog.append(db, entity: "numberSeries", id: id, action: "delete", at: Timestamps.string(now))
        }
    }
}
