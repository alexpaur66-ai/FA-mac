import Foundation
import GRDB
import InvoicingCore

/// A thing kept on the shelf (screens-flows.md §2n). It has no price: a line's price comes from the documents.
public struct StockItem: Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    /// Free text, like a document line's unit ("ks", "m").
    public var unit: String
    /// At or below this on hand the item is running low; nil never is.
    public var reorderLevel: Decimal?
    public var isArchived: Bool

    public init(id: String = UUID().uuidString, name: String, unit: String, reorderLevel: Decimal? = nil, isArchived: Bool = false) {
        self.id = id
        self.name = name
        self.unit = unit
        self.reorderLevel = reorderLevel
        self.isArchived = isArchived
    }
}

public enum StockMovementKind: String, Sendable, CaseIterable {
    /// Goods arrived (Receive…).
    case received = "in"
    /// Goods left: an issued invoice's line, or Take Out… for a sample or scrap.
    case takenOut = "out"
    /// A count of the shelf: sets on hand.
    case count
}

/// One change to an item, as its history shows it. Movements can't be edited; Undo deletes the latest.
public struct StockMovement: Hashable, Sendable, Identifiable {
    /// The order the movements were recorded in.
    public let sequence: Int64
    public let itemID: String
    public let kind: StockMovementKind
    public let day: CalendarDay
    /// Always 0 or more: the kind says the direction; a count's quantity is the counted figure.
    public let quantity: Decimal
    /// A count: the figure the app had before it.
    public let previousOnHand: Decimal?
    public let note: String?
    /// The issued document an "out" movement came from.
    public let documentID: String?
    public let documentNumber: String?
    public let customerName: String?

    public var id: Int64 { sequence }
}

/// An item with the figures the list shows.
public struct StockItemState: Hashable, Sendable, Identifiable {
    public let item: StockItem
    /// The latest count plus what came in and minus what went out after it; from 0 without a count, so it can
    /// be below zero (rule 1: rough on purpose).
    public let onHand: Decimal
    public let lastCounted: CalendarDay?
    public let movementCount: Int

    public var id: String { item.id }

    /// An item with a reorder level whose on hand is at or below it.
    public var isLow: Bool {
        guard let level = item.reorderLevel else { return false }
        return onHand <= level
    }
}

public enum StockError: Error, Equatable, Sendable {
    case itemNotFound(String)
    case nameRequired
    /// A listed item already has the name, ignoring case.
    case nameTaken(String)
    /// An item with movements is archived, not deleted.
    case itemHasMovements(String)
    /// Receive… and Take Out… need more than zero; a count 0 or more.
    case quantityNotPositive
    case quantityNegative
    /// A count can't be dated in the future.
    case dayInFuture
}

/// The link of a draft's line to an item, kept beside the document (rule 4).
public struct StockLineLink: Hashable, Sendable {
    public let documentID: String
    public let lineID: String
    public let itemID: String

    public init(documentID: String, lineID: String, itemID: String) {
        self.documentID = documentID
        self.lineID = lineID
        self.itemID = itemID
    }
}

/// Rough stock (screens-flows.md §2n, ADR 0013): the items, their movements, and on hand computed from them.
public struct StockStore: Sendable {
    let database: AppDatabase

    public init(_ database: AppDatabase) {
        self.database = database
    }

    // MARK: Reading

    /// The listed items with their figures, by name; archived items only when asked for.
    public func states(includeArchived: Bool = false) throws -> [StockItemState] {
        try database.queue.read { db in
            let items = try Self.items(db, includeArchived: includeArchived)
            let movements = try Self.movementFacts(db, itemID: nil)
            let grouped = Dictionary(grouping: movements, by: \.itemID)
            return items.map { Self.state($0, grouped[$0.id] ?? []) }
        }
    }

    public func state(id: String) throws -> StockItemState? {
        try database.queue.read { db in
            guard let item = try Self.item(db, id: id) else { return nil }
            return Self.state(item, try Self.movementFacts(db, itemID: id))
        }
    }

    /// The item's history, newest first: by day, then by the order recorded.
    public func movements(itemID: String) throws -> [StockMovement] {
        try database.queue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT m.*, d.number AS documentNumber, d.customerName AS customerName
                FROM stockMovement m LEFT JOIN document d ON d.id = m.documentID
                WHERE m.itemID = ? ORDER BY m.day DESC, m.sequence DESC
                """, arguments: [itemID])
            return try rows.map(Self.decodeMovement)
        }
    }

    // MARK: Items

    /// Adds an item; `onHand` records a count on `day`.
    @discardableResult
    public func add(name: String, unit: String, reorderLevel: Decimal? = nil, onHand: Decimal? = nil,
                    day: CalendarDay, now: Date = Date()) throws -> StockItem {
        let item = StockItem(name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                             unit: unit.trimmingCharacters(in: .whitespacesAndNewlines), reorderLevel: reorderLevel)
        if let onHand, onHand < 0 { throw StockError.quantityNegative }
        try database.queue.write { db in
            try Self.checkName(db, item.name, excluding: nil)
            let stamp = Timestamps.string(now)
            try Self.insert(db, item, createdAt: stamp, updatedAt: stamp)
            if let onHand {
                try Self.insertMovement(db, itemID: item.id, kind: .count, day: day, quantity: onHand, previousOnHand: 0,
                                        note: nil, documentID: nil, recordedAt: stamp)
            }
        }
        return item
    }

    /// Saves a new name, unit or reorder level. A new name changes no document; a new unit converts nothing.
    public func update(_ item: StockItem, now: Date = Date()) throws {
        var item = item
        item.name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
        item.unit = item.unit.trimmingCharacters(in: .whitespacesAndNewlines)
        try database.queue.write { db in
            guard try Self.item(db, id: item.id) != nil else { throw StockError.itemNotFound(item.id) }
            try Self.checkName(db, item.name, excluding: item.id)
            try db.execute(sql: "UPDATE stockItem SET name = ?, unit = ?, reorderLevel = ?, updatedAt = ? WHERE id = ?",
                           arguments: [item.name, item.unit, item.reorderLevel.map(Self.text), Timestamps.string(now), item.id])
        }
    }

    /// Hides an item with movements from the list and the editor's suggestions; its history stays.
    public func setArchived(id: String, archived: Bool, now: Date = Date()) throws {
        try database.queue.write { db in
            guard let item = try Self.item(db, id: id) else { throw StockError.itemNotFound(id) }
            if !archived { try Self.checkName(db, item.name, excluding: id) }
            let stamp = Timestamps.string(now)
            try db.execute(sql: "UPDATE stockItem SET archivedAt = ?, updatedAt = ? WHERE id = ?",
                           arguments: [archived ? stamp : nil, stamp, id])
        }
    }

    /// Deletes an item with no movements, with the links of draft lines to it; returns what `restore` needs to
    /// undo it.
    public func delete(id: String) throws -> (item: StockItem, links: [StockLineLink]) {
        try database.queue.write { db in
            guard let item = try Self.item(db, id: id) else { throw StockError.itemNotFound(id) }
            let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM stockMovement WHERE itemID = ?", arguments: [id]) ?? 0
            guard count == 0 else { throw StockError.itemHasMovements(id) }
            let links = try Row.fetchAll(db, sql: "SELECT * FROM documentLineStock WHERE itemID = ?", arguments: [id]).map {
                StockLineLink(documentID: $0["documentID"], lineID: $0["lineID"], itemID: $0["itemID"])
            }
            try db.execute(sql: "DELETE FROM documentLineStock WHERE itemID = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM stockItem WHERE id = ?", arguments: [id])
            return (item, links)
        }
    }

    /// Undo of `delete`: the item comes back with the links whose documents still exist.
    public func restore(_ item: StockItem, links: [StockLineLink], now: Date = Date()) throws {
        try database.queue.write { db in
            let stamp = Timestamps.string(now)
            try Self.insert(db, item, createdAt: stamp, updatedAt: stamp)
            for link in links {
                guard try Self.documentExists(db, link.documentID) else { continue }
                try db.execute(sql: "INSERT OR REPLACE INTO documentLineStock (documentID, lineID, itemID) VALUES (?, ?, ?)",
                               arguments: [link.documentID, link.lineID, link.itemID])
            }
        }
    }

    // MARK: Movements

    /// Goods arrived; more than zero.
    @discardableResult
    public func receive(itemID: String, quantity: Decimal, day: CalendarDay, note: String?, now: Date = Date()) throws -> Int64 {
        guard quantity > 0 else { throw StockError.quantityNotPositive }
        return try record(itemID: itemID, kind: .received, quantity: quantity, day: day, note: note, now: now)
    }

    /// Goods left without an invoice (a sample, scrap); more than zero.
    @discardableResult
    public func takeOut(itemID: String, quantity: Decimal, day: CalendarDay, note: String?, now: Date = Date()) throws -> Int64 {
        guard quantity > 0 else { throw StockError.quantityNotPositive }
        return try record(itemID: itemID, kind: .takenOut, quantity: quantity, day: day, note: note, now: now)
    }

    /// Sets on hand after counting the shelf; 0 or more, not in the future (`today` is the user's day).
    @discardableResult
    public func count(itemID: String, onHand: Decimal, day: CalendarDay, today: CalendarDay, now: Date = Date()) throws -> Int64 {
        guard onHand >= 0 else { throw StockError.quantityNegative }
        guard !(today < day) else { throw StockError.dayInFuture }
        return try record(itemID: itemID, kind: .count, quantity: onHand, day: day, note: nil, now: now)
    }

    /// Undo of a receive, take-out or count: deletes that movement.
    public func deleteMovement(sequence: Int64) throws {
        try database.queue.write { db in
            try db.execute(sql: "DELETE FROM stockMovement WHERE sequence = ?", arguments: [sequence])
        }
    }

    private func record(itemID: String, kind: StockMovementKind, quantity: Decimal, day: CalendarDay, note: String?,
                        now: Date) throws -> Int64 {
        try database.queue.write { db in
            guard let item = try Self.item(db, id: itemID) else { throw StockError.itemNotFound(itemID) }
            var previous: Decimal?
            if kind == .count {
                previous = Self.state(item, try Self.movementFacts(db, itemID: itemID)).onHand
            }
            let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
            return try Self.insertMovement(db, itemID: itemID, kind: kind, day: day, quantity: quantity, previousOnHand: previous,
                                           note: trimmed?.isEmpty == false ? trimmed : nil, documentID: nil,
                                           recordedAt: Timestamps.string(now))
        }
    }

    // MARK: On hand

    /// What on hand is computed from: one movement's kind, day, order and quantity.
    struct MovementFact: Sendable {
        let itemID: String
        let kind: StockMovementKind
        let day: CalendarDay
        let sequence: Int64
        let quantity: Decimal
        let fromDocument: Bool
    }

    /// On hand = the latest count + "in" after it − "out" after it, ordered by day, then by the order recorded.
    /// An issued document's "out" dated on the count's day is not after it: the count already saw the goods gone
    /// (screens-flows.md §2n, edge cases).
    static func onHand(_ facts: [MovementFact]) -> (onHand: Decimal, lastCounted: CalendarDay?) {
        let ordered = facts.sorted { ($0.day, $0.sequence) < ($1.day, $1.sequence) }
        let count = ordered.last { $0.kind == .count }
        var total = count?.quantity ?? 0
        for fact in ordered where fact.kind != .count {
            if let count {
                let after = count.day < fact.day || (fact.day == count.day && fact.sequence > count.sequence && !fact.fromDocument)
                guard after else { continue }
            }
            total += fact.kind == .received ? fact.quantity : -fact.quantity
        }
        return (total, count?.day)
    }

    static func state(_ item: StockItem, _ facts: [MovementFact]) -> StockItemState {
        let figures = onHand(facts)
        return StockItemState(item: item, onHand: figures.onHand, lastCounted: figures.lastCounted, movementCount: facts.count)
    }

    // MARK: Rows

    static func text(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).description(withLocale: Locale(identifier: "en_US_POSIX"))
    }

    static func decimal(_ text: String, table: String, id: String) throws -> Decimal {
        guard let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) else {
            throw DataError.corruptRecord(table: table, id: id, detail: "not a number: \(text)")
        }
        return value
    }

    static func items(_ db: Database, includeArchived: Bool) throws -> [StockItem] {
        let sql = includeArchived ? "SELECT * FROM stockItem" : "SELECT * FROM stockItem WHERE archivedAt IS NULL"
        return try Row.fetchAll(db, sql: sql).map(decodeItem)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func item(_ db: Database, id: String) throws -> StockItem? {
        try Row.fetchOne(db, sql: "SELECT * FROM stockItem WHERE id = ?", arguments: [id]).map(decodeItem)
    }

    static func decodeItem(_ row: Row) throws -> StockItem {
        let id: String = row["id"]
        let level: String? = row["reorderLevel"]
        return StockItem(id: id, name: row["name"], unit: row["unit"],
                         reorderLevel: try level.map { try decimal($0, table: "stockItem", id: id) },
                         isArchived: (row["archivedAt"] as String?) != nil)
    }

    static func movementFacts(_ db: Database, itemID: String?) throws -> [MovementFact] {
        let rows: [Row]
        if let itemID {
            rows = try Row.fetchAll(db, sql: "SELECT * FROM stockMovement WHERE itemID = ?", arguments: [itemID])
        } else {
            rows = try Row.fetchAll(db, sql: "SELECT * FROM stockMovement")
        }
        return try rows.map { row in
            let sequence: Int64 = row["sequence"]
            let id = String(sequence)
            let kindText: String = row["kind"]
            guard let kind = StockMovementKind(rawValue: kindText) else {
                throw DataError.corruptRecord(table: "stockMovement", id: id, detail: "kind \(kindText)")
            }
            let day: CalendarDay = try CalendarDay.stored(row["day"] as String, table: "stockMovement", id: id)
            return MovementFact(itemID: row["itemID"], kind: kind, day: day, sequence: sequence,
                                quantity: try decimal(row["quantity"], table: "stockMovement", id: id),
                                fromDocument: (row["documentID"] as String?) != nil)
        }
    }

    static func decodeMovement(_ row: Row) throws -> StockMovement {
        let sequence: Int64 = row["sequence"]
        let id = String(sequence)
        let kindText: String = row["kind"]
        guard let kind = StockMovementKind(rawValue: kindText) else {
            throw DataError.corruptRecord(table: "stockMovement", id: id, detail: "kind \(kindText)")
        }
        let day: CalendarDay = try CalendarDay.stored(row["day"] as String, table: "stockMovement", id: id)
        let previous: String? = row["previousOnHand"]
        return StockMovement(sequence: sequence, itemID: row["itemID"], kind: kind, day: day,
                             quantity: try decimal(row["quantity"], table: "stockMovement", id: id),
                             previousOnHand: try previous.map { try decimal($0, table: "stockMovement", id: id) },
                             note: row["note"], documentID: row["documentID"],
                             documentNumber: row["documentNumber"], customerName: row["customerName"])
    }

    /// An empty name, or one a listed item already has (ignoring case), is refused.
    static func checkName(_ db: Database, _ name: String, excluding id: String?) throws {
        guard !name.isEmpty else { throw StockError.nameRequired }
        let taken = try items(db, includeArchived: false).contains {
            $0.id != id && $0.name.compare(name, options: [.caseInsensitive], locale: Locale(identifier: "cs_CZ")) == .orderedSame
        }
        if taken { throw StockError.nameTaken(name) }
    }

    static func insert(_ db: Database, _ item: StockItem, createdAt: String, updatedAt: String) throws {
        try db.execute(sql: """
            INSERT INTO stockItem (id, name, unit, reorderLevel, archivedAt, createdAt, updatedAt) VALUES (?, ?, ?, ?, ?, ?, ?)
            """, arguments: [item.id, item.name, item.unit, item.reorderLevel.map(text), item.isArchived ? updatedAt : nil,
                             createdAt, updatedAt])
    }

    @discardableResult
    static func insertMovement(_ db: Database, itemID: String, kind: StockMovementKind, day: CalendarDay, quantity: Decimal,
                               previousOnHand: Decimal?, note: String?, documentID: String?, recordedAt: String) throws -> Int64 {
        try db.execute(sql: """
            INSERT INTO stockMovement (itemID, kind, day, quantity, previousOnHand, note, documentID, recordedAt)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [itemID, kind.rawValue, day.isoString, text(quantity), previousOnHand.map(text), note, documentID,
                             recordedAt])
        return db.lastInsertedRowID
    }

    static func documentExists(_ db: Database, _ id: String) throws -> Bool {
        try (Int.fetchOne(db, sql: "SELECT COUNT(*) FROM document WHERE id = ?", arguments: [id]) ?? 0) > 0
    }
}
