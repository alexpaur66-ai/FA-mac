import Foundation
import GRDB
import InvoicingCore

/// One item on the Issue sheet's stock row: its lines' quantities added up, and on hand after Issue.
public struct StockIssueRow: Hashable, Sendable, Identifiable {
    public let itemID: String
    public let name: String
    public let unit: String
    public let quantity: Decimal
    public let leftAfter: Decimal
    /// The DUZP is on or before the item's latest count: the count already saw the goods gone, so on hand
    /// doesn't change (screens-flows.md §2n, edge cases).
    public let countedAfterTaxPoint: Bool

    public var id: String { itemID }
}

/// The links of document lines to stock items (screens-flows.md §2c "Stock in the lines", §2n, ADR 0013 rule 4).
/// They live beside the document: its snapshot, hash and PDF never mention stock.
extension StockStore {
    /// Only an Invoice or a Final invoice takes goods out, at Issue (§2n rule 5).
    public static func takesGoodsOut(_ kind: DocumentKind) -> Bool {
        kind == .invoice || kind == .finalInvoice
    }

    /// Line id → item id for a document's linked lines.
    public func links(documentID: String) throws -> [String: String] {
        try database.queue.read { db in
            Dictionary(try Self.linkRows(db, documentID: documentID).map { ($0.lineID, $0.itemID) }, uniquingKeysWith: { first, _ in first })
        }
    }

    /// The document's links as rows, for an Undo that brings a deleted draft back.
    public func linkRows(documentID: String) throws -> [StockLineLink] {
        try database.queue.read { db in try Self.linkRows(db, documentID: documentID) }
    }

    /// Links a saved document's line to an item, replacing any link the line had.
    public func link(documentID: String, lineID: String, itemID: String) throws {
        try database.queue.write { db in
            guard try Self.item(db, id: itemID) != nil else { throw StockError.itemNotFound(itemID) }
            try db.execute(sql: "INSERT OR REPLACE INTO documentLineStock (documentID, lineID, itemID) VALUES (?, ?, ?)",
                           arguments: [documentID, lineID, itemID])
        }
    }

    /// Don't Take from Stock: the line keeps its text and takes nothing.
    public func unlink(documentID: String, lineID: String) throws {
        try database.queue.write { db in
            try db.execute(sql: "DELETE FROM documentLineStock WHERE documentID = ? AND lineID = ?", arguments: [documentID, lineID])
        }
    }

    /// Duplicate as Draft and Create Final Invoice copy the lines with their links; `lineIDs` maps each source
    /// line to its copy.
    public func copyLinks(from sourceID: String, to targetID: String, lineIDs: [String: String]) throws {
        try database.queue.write { db in
            for link in try Self.linkRows(db, documentID: sourceID) {
                guard let copy = lineIDs[link.lineID] else { continue }
                try db.execute(sql: "INSERT OR REPLACE INTO documentLineStock (documentID, lineID, itemID) VALUES (?, ?, ?)",
                               arguments: [targetID, copy, link.itemID])
            }
        }
    }

    /// Undo of Delete Draft: the links whose document and item still exist come back.
    public func restoreLinks(_ links: [StockLineLink]) throws {
        try database.queue.write { db in
            for link in links {
                guard try Self.documentExists(db, link.documentID), try Self.item(db, id: link.itemID) != nil else { continue }
                try db.execute(sql: "INSERT OR REPLACE INTO documentLineStock (documentID, lineID, itemID) VALUES (?, ?, ?)",
                               arguments: [link.documentID, link.lineID, link.itemID])
            }
        }
    }

    /// The unit price of the last issued line for the item in this currency (by issue date, then the time of
    /// Issue); nil when there is none. An item has no stored price (§2n rule 6).
    public func lastUnitPrice(itemID: String, currency: Currency) throws -> Decimal? {
        try database.queue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT l.documentID, l.lineID FROM documentLineStock l JOIN document d ON d.id = l.documentID
                WHERE l.itemID = ? AND d.status = ? AND d.currency = ?
                ORDER BY d.issueDate DESC, d.issuedAt DESC
                """, arguments: [itemID, DocumentStatus.issued.rawValue, currency.code])
            for row in rows {
                let documentID: String = row["documentID"]
                let lineID: String = row["lineID"]
                guard let document = try DocumentRecord.fetchOne(db, key: documentID)?.decode(),
                      let line = document.lines.first(where: { $0.id == lineID }) else { continue }
                return line.unitPrice
            }
            return nil
        }
    }

    /// What Issue would take out: each linked item once, in line order, with its lines' quantities added up
    /// and on hand after Issue. Empty for a document that takes nothing (§2n rule 5).
    public func issuePreview(documentID: String, kind: DocumentKind, lines: [DocumentLine], taxPoint: CalendarDay) throws -> [StockIssueRow] {
        guard Self.takesGoodsOut(kind) else { return [] }
        return try database.queue.read { db in
            let links = Dictionary(try Self.linkRows(db, documentID: documentID).map { ($0.lineID, $0.itemID) },
                                   uniquingKeysWith: { first, _ in first })
            var order: [String] = []
            var quantities: [String: Decimal] = [:]
            for line in lines where line.quantity > 0 {
                guard let itemID = links[line.id] else { continue }
                if quantities[itemID] == nil { order.append(itemID) }
                quantities[itemID, default: 0] += line.quantity
            }
            return try order.compactMap { itemID -> StockIssueRow? in
                guard let item = try Self.item(db, id: itemID), let quantity = quantities[itemID] else { return nil }
                var facts = try Self.movementFacts(db, itemID: itemID)
                let before = Self.onHand(facts)
                facts.append(MovementFact(itemID: itemID, kind: .takenOut, day: taxPoint, sequence: .max, quantity: quantity,
                                          fromDocument: true))
                let counted = before.lastCounted.map { !($0 < taxPoint) } ?? false
                return StockIssueRow(itemID: itemID, name: item.name, unit: item.unit, quantity: quantity,
                                     leftAfter: Self.onHand(facts).onHand, countedAfterTaxPoint: counted)
            }
        }
    }

    /// At Issue, inside its transaction: links of lines no longer in the document go, and each linked line of an
    /// Invoice or a Final invoice becomes an "out" movement of its quantity, dated the DUZP, with the document
    /// as its source. A line whose unit differs from the item's is taken as typed (no unit conversion).
    static func recordIssue(_ db: Database, document: Document, at stamp: String) throws {
        let present = Set(document.lines.map(\.id))
        let rows = try linkRows(db, documentID: document.id)
        for link in rows where !present.contains(link.lineID) {
            try db.execute(sql: "DELETE FROM documentLineStock WHERE documentID = ? AND lineID = ?",
                           arguments: [document.id, link.lineID])
        }
        guard takesGoodsOut(document.kind) else { return }
        let links = Dictionary(rows.map { ($0.lineID, $0.itemID) }, uniquingKeysWith: { first, _ in first })
        for line in document.lines where line.quantity > 0 {
            guard let itemID = links[line.id] else { continue }
            try insertMovement(db, itemID: itemID, kind: .takenOut, day: document.taxPoint, quantity: line.quantity,
                               previousOnHand: nil, note: nil, documentID: document.id, recordedAt: stamp)
        }
    }

    static func linkRows(_ db: Database, documentID: String) throws -> [StockLineLink] {
        try Row.fetchAll(db, sql: "SELECT * FROM documentLineStock WHERE documentID = ?", arguments: [documentID]).map {
            StockLineLink(documentID: $0["documentID"], lineID: $0["lineID"], itemID: $0["itemID"])
        }
    }
}

/// One row of a client page's Items tab (screens-flows.md §2n "On the client page"): what the client bought of
/// one stock item, from the "out" movements of their issued documents.
public struct ClientStockItem: Hashable, Sendable, Identifiable {
    public let itemID: String
    public let name: String
    public let unit: String
    public let boughtThisYear: Decimal
    public let boughtInAll: Decimal
    /// The DUZP of the last document that took the item out, and that document.
    public let lastDay: CalendarDay
    public let lastDocumentID: String
    public let lastDocumentNumber: String?
    /// The unit price on that document's line, in its currency; nil when the line can't be found.
    public let lastPrice: Money?

    public var id: String { itemID }
}

extension StockStore {
    /// The Items tab of a client: every item that left stock on one of the client's issued documents, archived
    /// items too, by name. "This year" is the year of the movement's day (the DUZP).
    public func clientItems(customerID: String, year: Int) throws -> [ClientStockItem] {
        try database.queue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT m.sequence, m.itemID, m.day, m.quantity, m.documentID, d.number AS documentNumber
                FROM stockMovement m JOIN document d ON d.id = m.documentID
                WHERE m.kind = ? AND d.customerID = ? AND d.status = ?
                """, arguments: [StockMovementKind.takenOut.rawValue, customerID, DocumentStatus.issued.rawValue])
            struct Out {
                let sequence: Int64
                let itemID: String
                let day: CalendarDay
                let quantity: Decimal
                let documentID: String
                let documentNumber: String?
            }
            let outs = try rows.map { row -> Out in
                let sequence: Int64 = row["sequence"]
                let id = String(sequence)
                return Out(sequence: sequence, itemID: row["itemID"],
                           day: try CalendarDay.stored(row["day"] as String, table: "stockMovement", id: id),
                           quantity: try Self.decimal(row["quantity"], table: "stockMovement", id: id),
                           documentID: row["documentID"], documentNumber: row["documentNumber"])
            }
            var result: [ClientStockItem] = []
            for (itemID, group) in Dictionary(grouping: outs, by: \.itemID) {
                guard let stockItem = try Self.item(db, id: itemID),
                      let last = group.max(by: { ($0.day, $0.sequence) < ($1.day, $1.sequence) }) else { continue }
                let thisYear = group.filter { $0.day.year == year }.reduce(Decimal(0)) { $0 + $1.quantity }
                let all = group.reduce(Decimal(0)) { $0 + $1.quantity }
                var price: Money?
                if let document = try DocumentRecord.fetchOne(db, key: last.documentID)?.decode() {
                    let lineIDs = Set(try Self.linkRows(db, documentID: last.documentID).filter { $0.itemID == itemID }.map(\.lineID))
                    if let line = document.lines.first(where: { lineIDs.contains($0.id) }) {
                        price = Money(line.unitPrice, document.currency)
                    }
                }
                result.append(ClientStockItem(itemID: itemID, name: stockItem.name, unit: stockItem.unit, boughtThisYear: thisYear,
                                              boughtInAll: all, lastDay: last.day, lastDocumentID: last.documentID,
                                              lastDocumentNumber: last.documentNumber, lastPrice: price))
            }
            return result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }
}
