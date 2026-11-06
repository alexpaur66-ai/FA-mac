import Foundation
import GRDB
import InvoicingCore

/// A note on a client's Activity tab (screens-flows.md §2e, other-07): what was agreed on a call, for example.
public struct ClientNote: Hashable, Sendable, Identifiable {
    public let id: String
    public let customerID: String
    /// The day the note is about: the day it was written, unless changed.
    public var day: CalendarDay
    public var text: String
    /// ISO 8601 UTC.
    public let createdAt: String
    public let updatedAt: String
}

public enum ClientNoteError: Error, Equatable, Sendable {
    /// A note needs some text.
    case textRequired
    case noteNotFound(String)
}

struct ClientNoteRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "clientNote"
    var id: String
    var customerID: String
    var day: String
    var text: String
    var createdAt: String
    var updatedAt: String

    init(_ note: ClientNote) {
        id = note.id
        customerID = note.customerID
        day = note.day.isoString
        text = note.text
        createdAt = note.createdAt
        updatedAt = note.updatedAt
    }

    func note() throws -> ClientNote {
        ClientNote(id: id, customerID: customerID, day: try CalendarDay.stored(day, table: Self.databaseTableName, id: id),
                   text: text, createdAt: createdAt, updatedAt: updatedAt)
    }
}

/// The client notes, and the document events the Activity tab shows beside them.
public struct ClientNoteStore: Sendable {
    let database: AppDatabase

    public init(_ database: AppDatabase) {
        self.database = database
    }

    /// The client's notes, newest first: by day, then by when they were written.
    public func notes(customerID: String) throws -> [ClientNote] {
        try database.queue.read { db in
            try ClientNoteRecord.filter(Column("customerID") == customerID)
                .order(Column("day").desc, Column("createdAt").desc, Column("id"))
                .fetchAll(db).map { try $0.note() }
        }
    }

    /// Adds a note to the client. The text is trimmed; an empty one throws `textRequired`.
    @discardableResult
    public func add(customerID: String, text: String, day: CalendarDay, id: String = UUID().uuidString,
                    now: Date = Date()) throws -> ClientNote {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ClientNoteError.textRequired }
        let stamp = Timestamps.string(now)
        let note = ClientNote(id: id, customerID: customerID, day: day, text: trimmed, createdAt: stamp, updatedAt: stamp)
        try database.queue.write { db in
            guard try CustomerRecord.exists(db, key: customerID) else { throw DataError.customerNotFound(customerID) }
            try ClientNoteRecord(note).insert(db)
            try AuditLog.append(db, entity: "clientNote", id: id, action: "create", details: ["customer": customerID], at: stamp)
        }
        return note
    }

    /// Changes a note's text and day; returns the note as it was, for Undo.
    @discardableResult
    public func update(id: String, text: String, day: CalendarDay, now: Date = Date()) throws -> ClientNote {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ClientNoteError.textRequired }
        return try database.queue.write { db in
            guard var record = try ClientNoteRecord.fetchOne(db, key: id) else { throw ClientNoteError.noteNotFound(id) }
            let before = try record.note()
            let stamp = Timestamps.string(now)
            record.text = trimmed
            record.day = day.isoString
            record.updatedAt = stamp
            try record.update(db)
            try AuditLog.append(db, entity: "clientNote", id: id, action: "update", at: stamp)
            return before
        }
    }

    /// Deletes a note; returns it, so Undo can put it back with `restore`.
    @discardableResult
    public func delete(id: String, now: Date = Date()) throws -> ClientNote {
        try database.queue.write { db in
            guard let record = try ClientNoteRecord.fetchOne(db, key: id) else { throw ClientNoteError.noteNotFound(id) }
            let note = try record.note()
            try ClientNoteRecord.deleteOne(db, key: id)
            try AuditLog.append(db, entity: "clientNote", id: id, action: "delete", at: Timestamps.string(now))
            return note
        }
    }

    /// Undo of a delete: the note comes back as it was, under its id. Nothing happens when its client is gone
    /// or the note is already there; false then, so the Undo registers no Redo.
    @discardableResult
    public func restore(_ note: ClientNote, now: Date = Date()) throws -> Bool {
        try database.queue.write { db -> Bool in
            guard try CustomerRecord.exists(db, key: note.customerID),
                  try !ClientNoteRecord.exists(db, key: note.id) else { return false }
            try ClientNoteRecord(note).insert(db)
            try AuditLog.append(db, entity: "clientNote", id: note.id, action: "restore", at: Timestamps.string(now))
            return true
        }
    }

    /// The audit events of the client's documents that the Activity tab shows (issue, payments, closing events),
    /// oldest first, each with its document id.
    public func documentEvents(documentIDs: [String]) throws -> [AuditEvent] {
        guard !documentIDs.isEmpty else { return [] }
        return try database.queue.read { db in
            try AuditEventRecord
                .filter(Column("entity") == "document" && documentIDs.contains(Column("entityID"))
                        && Self.clientActions.contains(Column("action")))
                .order(Column("id"))
                .fetchAll(db)
                .map { try $0.event() }
        }
    }

    /// The document events that belong in a client's history; the PDF renders and saves stay on the document.
    static let clientActions = ["issue", "payment", "paymentDeleted", "close", "reopen"]
}
